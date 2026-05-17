import Foundation
import Combine
import OSLog

/// Manages a pre-generated buffer of audio files. Mirrors Android `AudioBufferManager`.
/// Worker auto-triggers the next generation after each stream completes, keeping the queue
/// ahead of playback. Context changes call `drainAndReprime` which bumps the epoch and
/// discards stale in-flight chunks.
final class AudioBufferManager: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "AudioBufferManager")
    private static let maxHistory = 50
    private static let maxConcurrentGenerations = 2

    // ── Dependencies ──────────────────────────────────────────────────────

    private let musicRepository: GenerationRepository
    private let paramsBuilder: ParamsBuilder
    private let promptBuilder: PromptBuilder
    private let userAdjustmentRepository: UserAdjustmentRepository
    private let lastSessionParams: LastSessionParamsStore
    private let audioCacheDir: URL

    // ── Queue ─────────────────────────────────────────────────────────────

    private var queue: [URL] = []
    private var queueWaiters: [CheckedContinuation<URL?, Never>] = []
    private let queueLock = NSLock()

    /// Pending generation requests. `Unit` semantics — just a signal.
    private let requestStream: AsyncStream<Void>
    private let requestContinuation: AsyncStream<Void>.Continuation

    // ── State ─────────────────────────────────────────────────────────────

    private var generationEpoch: Int64 = 0
    private var sessionMentalState: MentalState?
    private var sessionParams: SongParams?
    private var previousSongParams: SongParams?
    private var currentSensorState = SensorState()
    private var currentScene: Scene?
    private var activeTasks: [Task<Void, Never>] = []
    private let stateLock = NSLock()

    // ── Published state for UI ────────────────────────────────────────────

    @Published private(set) var chunksReady: Int = 0
    @Published private(set) var currentMetricsContext: String = ""
    @Published private(set) var currentSongParams: SongParams?
    @Published private(set) var currentMentalState: MentalState?
    @Published private(set) var lastError: String?
    @Published private(set) var songHistory: [GeneratedSong] = []
    @Published private(set) var playbackProgress = PlaybackProgress()
    @Published private(set) var hasPrevious: Bool = false

    init(
        musicRepository: GenerationRepository,
        paramsBuilder: ParamsBuilder,
        promptBuilder: PromptBuilder,
        userAdjustmentRepository: UserAdjustmentRepository,
        lastSessionParams: LastSessionParamsStore,
        audioCacheDir: URL
    ) {
        self.musicRepository = musicRepository
        self.paramsBuilder = paramsBuilder
        self.promptBuilder = promptBuilder
        self.userAdjustmentRepository = userAdjustmentRepository
        self.lastSessionParams = lastSessionParams
        self.audioCacheDir = audioCacheDir

        var continuation: AsyncStream<Void>.Continuation!
        self.requestStream = AsyncStream<Void> { c in continuation = c }
        self.requestContinuation = continuation

        startWorker()
    }

    // ── Public API ─────────────────────────────────────────────────────────

    func updateHasPrevious(_ value: Bool) {
        DispatchQueue.main.async { self.hasPrevious = value }
    }

    func updateProgress(positionMs: Int64, durationMs: Int64) {
        DispatchQueue.main.async {
            self.playbackProgress = PlaybackProgress(positionMs: positionMs, durationMs: durationMs)
        }
    }

    var hasBufferedAudio: Bool {
        queueLock.lock(); defer { queueLock.unlock() }
        return !queue.isEmpty
    }

    /// Start a new playback session. Clears cached mental state and params so the next
    /// generation runs the full pipeline. May reuse a fresh cached session via lastSessionParams.
    func prime(sensorState: SensorState, scene: Scene?) async {
        let resuming = hasBufferedAudio
        if resuming {
            Self.log.debug("prime: resuming with buffered chunks")
        } else {
            cleanAudioCache()
            await MainActor.run {
                self.chunksReady = 0
                self.currentMetricsContext = ""
                self.currentSongParams = nil
                self.currentMentalState = nil
            }
        }
        stateLock.lock()
        sessionMentalState = nil
        sessionParams = nil
        previousSongParams = nil
        stateLock.unlock()

        if let cached = await lastSessionParams.load(),
           lastSessionParams.isFreshFor(cached, currentScene: scene, currentHr: sensorState.heartRate) {
            Self.log.debug("prime: reusing persisted params")
            stateLock.lock()
            sessionParams = cached.params
            sessionMentalState = cached.mentalState
            stateLock.unlock()
            await MainActor.run {
                self.currentSongParams = cached.params
                self.currentMentalState = cached.mentalState
            }
        }

        enqueueGeneration(sensorState: sensorState, scene: scene)
    }

    /// Applies a user-initiated music adjustment (genre, energy, free text).
    func applyUserAdjustment(sensorState: SensorState, scene: Scene?) {
        stateLock.lock(); sessionParams = nil; stateLock.unlock()
        drainAndReprime(sensorState: sensorState, scene: scene)
    }

    /// Cancel in-flight generation, flush queue, restart with new context. Bumps epoch.
    func drainAndReprime(sensorState: SensorState, scene: Scene?) {
        cancelActiveTasks()
        stateLock.lock(); generationEpoch += 1; stateLock.unlock()
        flushQueue()
        DispatchQueue.main.async {
            self.chunksReady = 0
            self.lastError = nil
        }
        enqueueGeneration(sensorState: sensorState, scene: scene)
    }

    func retryGeneration() {
        DispatchQueue.main.async { self.lastError = nil }
        requestContinuation.yield()
    }

    func notifySkipToNext() {
        DispatchQueue.main.async { self.chunksReady = 0 }
    }

    func cancelGeneration() {
        cancelActiveTasks()
        stateLock.lock()
        generationEpoch += 1
        sessionMentalState = nil
        sessionParams = nil
        previousSongParams = nil
        stateLock.unlock()
        flushQueue()
        DispatchQueue.main.async {
            self.chunksReady = 0
            self.lastError = nil
        }
        Self.log.debug("Generation cancelled, buffer cleared")
    }

    func updateSensorState(_ state: SensorState) {
        stateLock.lock(); currentSensorState = state; stateLock.unlock()
    }

    func updateScene(_ scene: Scene?) {
        stateLock.lock(); currentScene = scene; stateLock.unlock()
    }

    func takeNext() async -> URL? {
        queueLock.lock()
        if let file = queue.first {
            queue.removeFirst()
            queueLock.unlock()
            return file
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            queueWaiters.append(cont)
            queueLock.unlock()
        }
    }

    /// Records a song as completed in the history. Called by the worker on first chunk.
    private func recordSong(_ params: SongParams) {
        let id = Int64(Date().timeIntervalSince1970 * 1000)
        let song = GeneratedSong(
            id: id,
            params: params,
            mentalState: currentMentalState,
            scene: currentScene,
            generatedAt: id,
        )
        DispatchQueue.main.async {
            var next = self.songHistory
            next.insert(song, at: 0)
            if next.count > Self.maxHistory { next = Array(next.prefix(Self.maxHistory)) }
            self.songHistory = next
        }
    }

    /// Deletes all MP3 files from the audio cache directory.
    func cleanAudioCache() {
        if let files = try? FileManager.default.contentsOfDirectory(at: audioCacheDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "mp3" {
                try? FileManager.default.removeItem(at: file)
            }
        }
        DispatchQueue.main.async { self.hasPrevious = false }
    }

    // ── Worker ─────────────────────────────────────────────────────────────

    private func startWorker() {
        Task.detached { [weak self] in
            guard let self else { return }
            Self.log.debug("Worker started")
            for await _ in self.requestStream {
                let t: Task<Void, Never> = Task.detached { [weak self] in
                    await self?.processNextRequest()
                }
                self.stateLock.lock()
                self.activeTasks.removeAll { $0.isCancelled }
                self.activeTasks.append(t)
                self.stateLock.unlock()
            }
        }
    }

    private func processNextRequest() async {
        stateLock.lock()
        let myEpoch = generationEpoch
        let state = currentSensorState
        let scene = currentScene
        stateLock.unlock()

        let metrics = promptBuilder.buildMetricsContext(state: state, scene: scene)
        await MainActor.run { self.currentMetricsContext = metrics }

        // Three-path param resolution:
        //   1. sessionParams != null → reuse
        //   2. sessionMentalState != null → Step 1b only
        //   3. Both null → full re-query Step 1a + 1b
        let params: SongParams
        stateLock.lock()
        let cachedParams = sessionParams
        let cachedMental = sessionMentalState
        stateLock.unlock()

        if let p = cachedParams {
            params = p
        } else if let ms = cachedMental {
            Self.log.debug("Worker: cached MentalState found — running Step 1b only")
            stateLock.lock(); let prevForRequery = previousSongParams; stateLock.unlock()
            if let rederived = await musicRepository.translateMentalState(ms, previousParams: prevForRequery) {
                stateLock.lock(); sessionParams = rederived; stateLock.unlock()
                await lastSessionParams.save(params: rederived, mentalState: ms, scene: scene, heartRate: state.heartRate)
                params = rederived
            } else {
                Self.log.warning("Worker: Step 1b re-query failed — falling back to full re-query")
                do {
                    let p = try await paramsBuilder.buildParams(state: state, scene: scene)
                    let newMS = musicRepository.translatedMentalStateValue
                    stateLock.lock()
                    sessionMentalState = newMS
                    sessionParams = p
                    stateLock.unlock()
                    await lastSessionParams.save(params: p, mentalState: newMS, scene: scene, heartRate: state.heartRate)
                    params = p
                } catch {
                    await MainActor.run { self.lastError = error.localizedDescription }
                    return
                }
            }
        } else {
            Self.log.debug("Worker: new session — running full re-query")
            do {
                let p = try await paramsBuilder.buildParams(state: state, scene: scene)
                let newMS = musicRepository.translatedMentalStateValue
                stateLock.lock()
                sessionMentalState = newMS
                sessionParams = p
                stateLock.unlock()
                await lastSessionParams.save(params: p, mentalState: newMS, scene: scene, heartRate: state.heartRate)
                params = p
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
                return
            }
        }

        await MainActor.run {
            self.currentSongParams = params
            self.currentMentalState = self.sessionMentalState
        }

        stateLock.lock(); let currentEpoch = generationEpoch; stateLock.unlock()
        if myEpoch != currentEpoch {
            Self.log.debug("Worker: epoch changed before streaming — discarding")
            return
        }

        // Pre-trigger next song generation NOW so its Step 1b overlaps with this song's Step 2.
        stateLock.lock()
        previousSongParams = params
        sessionParams = nil
        stateLock.unlock()
        Self.log.debug("Worker: pre-triggering next song before Step 2")
        requestContinuation.yield()

        var firstChunk = true
        for await chunk in musicRepository.generateAudioStream(params: params) {
            stateLock.lock(); let epochNow = generationEpoch; stateLock.unlock()
            switch chunk {
            case .audio(let file, let index, _):
                if myEpoch != epochNow {
                    try? FileManager.default.removeItem(at: file)
                    Self.log.debug("Worker: stale chunk discarded")
                    continue
                }
                if firstChunk {
                    firstChunk = false
                    recordSong(params)
                }
                Self.log.debug("Worker: queuing chunk \(index)")
                enqueueFile(file)
            case .error(let message):
                Self.log.error("Worker: stream error — \(message)")
                if myEpoch == epochNow {
                    await MainActor.run { self.lastError = message }
                    stateLock.lock(); sessionParams = params; stateLock.unlock()
                }
            case .complete:
                Self.log.debug("Worker: stream complete")
            }
        }
    }

    private func enqueueGeneration(sensorState: SensorState, scene: Scene?) {
        stateLock.lock(); currentSensorState = sensorState; currentScene = scene; stateLock.unlock()
        requestContinuation.yield()
    }

    private func enqueueFile(_ file: URL) {
        queueLock.lock()
        if let waiter = queueWaiters.first {
            queueWaiters.removeFirst()
            queueLock.unlock()
            waiter.resume(returning: file)
        } else {
            queue.append(file)
            queueLock.unlock()
        }
        DispatchQueue.main.async { self.chunksReady += 1 }
    }

    private func flushQueue() {
        queueLock.lock()
        let toDelete = queue
        queue.removeAll()
        let waiters = queueWaiters
        queueWaiters.removeAll()
        queueLock.unlock()
        for file in toDelete {
            try? FileManager.default.removeItem(at: file)
        }
        for w in waiters { w.resume(returning: nil) }
    }

    private func cancelActiveTasks() {
        stateLock.lock()
        let tasks = activeTasks
        activeTasks.removeAll()
        stateLock.unlock()
        for t in tasks { t.cancel() }
    }
}
