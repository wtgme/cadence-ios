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
    /// Minimum gap between two Step 1a estimates triggered by context shifts.
    private static let mentalStateMinReestimateIntervalMs: Int64 = 60_000

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
    /// Mental state estimated by Step 1a. Set by `prime` at session start and refreshed by
    /// `drainAndReprime` when context shifts (HR drift / scene change), subject to a
    /// `mentalStateMinReestimateIntervalMs` floor to prevent rapid flapping. Cleared on
    /// `cancelGeneration` and the next `prime`. Survives `applyUserAdjustment` — the user's
    /// physiology didn't change, only their stated preference.
    private var sessionMentalState: MentalState?
    /// Wall-clock timestamp (epoch ms) of the last successful Step 1a estimate, or the cache
    /// load time when `prime` reused a persisted estimate. Used by `drainAndReprime` to gate
    /// re-estimation so HR drift / scene change can't fire Step 1a back-to-back.
    private var lastMentalStateEstimateMs: Int64 = 0
    private var sessionParams: SongParams?
    private var previousSongParams: SongParams?
    private var currentSensorState = SensorState()
    private var currentScene: Scene?
    private var activeTasks: [Task<Void, Never>] = []
    private let stateLock = NSLock()
    private let generationSemaphore = GenerationSemaphore(limit: AudioBufferManager.maxConcurrentGenerations)

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
        lastMentalStateEstimateMs = 0
        stateLock.unlock()

        if let cached = await lastSessionParams.load(),
           lastSessionParams.isFreshFor(cached, currentScene: scene, currentHr: sensorState.heartRate) {
            Self.log.debug("prime: reusing persisted params")
            stateLock.lock()
            sessionParams = cached.params
            sessionMentalState = cached.mentalState
            // Seed the timestamp from the persisted save time so a 10-min-old cache
            // doesn't suppress re-estimation on the next drainAndReprime.
            lastMentalStateEstimateMs = cached.savedAtMs
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
    ///
    /// If the cached Step 1a estimate is older than `mentalStateMinReestimateIntervalMs`,
    /// clear it so the next request re-runs Step 1a with fresh biometrics. Within the floor
    /// the cached state is kept and only Step 1b will re-run (path 2 in `processNextRequest`).
    func drainAndReprime(sensorState: SensorState, scene: Scene?) {
        cancelActiveTasks()
        stateLock.lock(); generationEpoch += 1; stateLock.unlock()
        flushQueue()
        DispatchQueue.main.async {
            self.chunksReady = 0
            self.lastError = nil
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        stateLock.lock()
        let lastEstimate = lastMentalStateEstimateMs
        let ageMs = now - lastEstimate
        if lastEstimate > 0 && ageMs >= Self.mentalStateMinReestimateIntervalMs {
            Self.log.debug("drainAndReprime: invalidating MentalState (age=\(ageMs / 1000)s) — Step 1a will re-run")
            sessionMentalState = nil
            sessionParams = nil
        } else {
            Self.log.debug("drainAndReprime: keeping MentalState (age=\(ageMs / 1000)s, floor=\(Self.mentalStateMinReestimateIntervalMs / 1000)s) — Step 1b only")
        }
        stateLock.unlock()

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
        lastMentalStateEstimateMs = 0
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
                // Cap concurrent generations to MAX_CONCURRENT_GENERATIONS, matching
                // Android's Semaphore. Without this, each worker's pre-trigger spawns
                // another worker unconditionally and they run in parallel — which under
                // failure conditions (no API key, server timeout) snowballs into many
                // simultaneous in-flight requests.
                await self.generationSemaphore.acquire()
                let t: Task<Void, Never> = Task.detached { [weak self] in
                    guard let self else { return }
                    await self.processNextRequest()
                    await self.generationSemaphore.release()
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
                    lastMentalStateEstimateMs = Int64(Date().timeIntervalSince1970 * 1000)
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
                lastMentalStateEstimateMs = Int64(Date().timeIntervalSince1970 * 1000)
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
        // Skip the pre-trigger when we're in pure-fallback mode (no Signal2Style key): there
        // is no Step 1b to overlap with, and chained pre-triggers under repeated streaming
        // failure produce a flood of in-flight requests with no useful overlap.
        let usingFallback = musicRepository.translatedMentalStateValue == nil
        stateLock.lock()
        previousSongParams = params
        if !usingFallback { sessionParams = nil }
        stateLock.unlock()
        if !usingFallback {
            Self.log.debug("Worker: pre-triggering next song before Step 2")
            requestContinuation.yield()
        } else {
            Self.log.debug("Worker: fallback mode (no LLM) — skipping pre-trigger")
        }

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
                // In fallback mode we deliberately don't pre-trigger before streaming,
                // so trigger the next generation here once this one finishes successfully.
                if usingFallback && myEpoch == epochNow {
                    stateLock.lock(); sessionParams = nil; stateLock.unlock()
                    requestContinuation.yield()
                }
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
