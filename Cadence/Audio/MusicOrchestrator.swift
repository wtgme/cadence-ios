import Foundation
import Combine
import OSLog

/// Singleton orchestrating scene detection, generation triggering, and playback.
/// Monitors HR drift (±15 bpm) and scene changes to reprime the buffer.
final class MusicOrchestrator: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "MusicOrchestrator")
    /// Only regenerate music when HR changes by ±15 bpm.
    private static let hrDriftThreshold = 15

    // ── Dependencies ──────────────────────────────────────────────────────

    let sensorStateCollector: SensorStateCollector
    private let sceneDetector: SceneDetector
    private let sceneStateMachine: SceneStateMachine
    let bufferManager: AudioBufferManager
    private let tasteMemoryRepository: TasteMemoryRepository
    let userAdjustmentRepository: UserAdjustmentRepository

    private(set) lazy var musicPlayer = MusicPlayer(bufferManager: bufferManager)

    // ── Published state ───────────────────────────────────────────────────

    @Published private(set) var currentScene: Scene?
    @Published private(set) var candidateScene: Scene?
    @Published private(set) var currentSensorState = SensorState()
    @Published private(set) var hasHealthPermissions = true
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var isAdaptingToHrDrift = false

    var healthDiagnosticPublisher: AnyPublisher<String?, Never> { sensorStateCollector.healthDiagnostic }

    // Forwarded buffer state
    var chunksReadyPublisher: AnyPublisher<Int, Never> { bufferManager.$chunksReady.eraseToAnyPublisher() }
    var currentMetricsContextPublisher: AnyPublisher<String, Never> { bufferManager.$currentMetricsContext.eraseToAnyPublisher() }
    var currentSongParamsPublisher: AnyPublisher<SongParams?, Never> { bufferManager.$currentSongParams.eraseToAnyPublisher() }
    var currentMentalStatePublisher: AnyPublisher<MentalState?, Never> { bufferManager.$currentMentalState.eraseToAnyPublisher() }
    var lastErrorPublisher: AnyPublisher<String?, Never> { bufferManager.$lastError.eraseToAnyPublisher() }
    var songHistoryPublisher: AnyPublisher<[GeneratedSong], Never> { bufferManager.$songHistory.eraseToAnyPublisher() }
    var playbackProgressPublisher: AnyPublisher<PlaybackProgress, Never> { bufferManager.$playbackProgress.eraseToAnyPublisher() }
    var hasPreviousPublisher: AnyPublisher<Bool, Never> { bufferManager.$hasPrevious.eraseToAnyPublisher() }

    var currentAdjustmentPublisher: AnyPublisher<UserMusicAdjustment, Never> {
        (userAdjustmentRepository as UserAdjustmentRepository).$adjustment.eraseToAnyPublisher()
    }
    var tasteMemoryPublisher: AnyPublisher<UserTasteMemory, Never> { tasteMemoryRepository.tasteMemoryPublisher }

    // ── Internal ──────────────────────────────────────────────────────────

    private var cancellables = Set<AnyCancellable>()
    private var playbackStarted = false
    /// HR at last generation — only regenerate on significant drift.
    private var lastGeneratedHr = 0
    private var sensorSubscription: AnyCancellable?
    private var sceneSubscription: AnyCancellable?
    private var chunksSubscription: AnyCancellable?

    init(
        sensorStateCollector: SensorStateCollector,
        sceneDetector: SceneDetector,
        sceneStateMachine: SceneStateMachine,
        bufferManager: AudioBufferManager,
        tasteMemoryRepository: TasteMemoryRepository,
        userAdjustmentRepository: UserAdjustmentRepository
    ) {
        self.sensorStateCollector = sensorStateCollector
        self.sceneDetector = sceneDetector
        self.sceneStateMachine = sceneStateMachine
        self.bufferManager = bufferManager
        self.tasteMemoryRepository = tasteMemoryRepository
        self.userAdjustmentRepository = userAdjustmentRepository
    }

    // ── Detection lifecycle ───────────────────────────────────────────────

    func startDetection() {
        if sensorSubscription != nil { return }
        sensorStateCollector.start()

        sensorSubscription = sensorStateCollector.$sensorState
            .sink { [weak self] state in self?.onSensorState(state) }

        sceneSubscription = sceneStateMachine.confirmedScenePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scene in self?.onSceneConfirmed(scene) }
    }

    func startPlayback() {
        startDetection()
        playbackStarted = true
        DispatchQueue.main.async { self.playbackState = .buffering }

        Task { [weak self] in
            guard let self else { return }
            Self.log.debug("startPlayback: refreshing biometrics before generation")
            await self.sensorStateCollector.refreshAll()

            self.lastGeneratedHr = self.currentSensorState.heartRate
            await self.bufferManager.prime(sensorState: self.currentSensorState, scene: self.currentScene)

            // Wait for first chunk then start playback.
            await self.waitForChunks(minimum: 1)
            await MainActor.run {
                self.playbackState = .playing
                self.musicPlayer.startPlayback()
            }
            self.subscribeChunksReady()
        }
    }

    func stop() {
        playbackStarted = false
        isAdaptingToHrDrift = false
        sceneStateMachine.resetOverride()
        DispatchQueue.main.async { self.playbackState = .idle }
        sensorSubscription?.cancel(); sensorSubscription = nil
        sceneSubscription?.cancel(); sceneSubscription = nil
        chunksSubscription?.cancel(); chunksSubscription = nil
        bufferManager.cancelGeneration()
        userAdjustmentRepository.reset()
        sensorStateCollector.stop()
        musicPlayer.stop()
    }

    func retryGeneration() { bufferManager.retryGeneration() }

    func skipToNext() {
        guard playbackStarted else { return }
        musicPlayer.skipToNext()
    }

    func skipToPrevious() {
        guard playbackStarted else { return }
        musicPlayer.skipToPrevious()
    }

    func seek(positionMs: Int64) {
        guard playbackStarted else { return }
        musicPlayer.seek(positionMs: positionMs)
    }

    func forceScene(_ scene: Scene) { sceneStateMachine.forceScene(scene) }
    func clearSceneOverride() { sceneStateMachine.resetOverride() }

    func refreshBiometrics() async {
        let granted = await sensorStateCollector.hasHeartRatePermission()
        await MainActor.run { self.hasHealthPermissions = granted }
        await sensorStateCollector.refreshAll()
        await MainActor.run { self.currentSensorState = self.sensorStateCollector.sensorState }
    }

    func checkHealthPermissions() async {
        let granted = await sensorStateCollector.hasHeartRatePermission()
        await MainActor.run { self.hasHealthPermissions = granted }
    }

    // ── User music adjustment ─────────────────────────────────────────────

    func toggleGenre(_ genre: String) {
        userAdjustmentRepository.toggleGenre(genre)
        if playbackStarted {
            bufferManager.applyUserAdjustment(sensorState: currentSensorState, scene: currentScene)
        }
    }

    func clearGenres() {
        userAdjustmentRepository.clearGenres()
        if playbackStarted {
            bufferManager.applyUserAdjustment(sensorState: currentSensorState, scene: currentScene)
        }
    }

    func setEnergyBias(_ delta: Int) {
        userAdjustmentRepository.setEnergyBias(delta)
        if playbackStarted {
            bufferManager.applyUserAdjustment(sensorState: currentSensorState, scene: currentScene)
        }
    }

    func submitFreeText(_ text: String) {
        userAdjustmentRepository.setFreeText(text)
        if playbackStarted {
            bufferManager.applyUserAdjustment(sensorState: currentSensorState, scene: currentScene)
        }
    }

    // ── Taste feedback ────────────────────────────────────────────────────

    func recordListenResult(params: SongParams, listenFraction: Float) {
        let signal: Float
        if listenFraction >= 0.9 { signal = 1.0 }
        else if listenFraction >= 0.5 { signal = 0.5 }
        else if listenFraction >= 0.1 { signal = -0.5 }
        else { signal = -1.0 }
        Task { await tasteMemoryRepository.recordFeedback(params: params, scene: currentScene, signal: signal) }
    }

    func resetTasteMemory() {
        Task { await tasteMemoryRepository.reset() }
    }

    // MARK: - Internal handlers

    private func onSensorState(_ state: SensorState) {
        DispatchQueue.main.async { self.currentSensorState = state }
        bufferManager.updateSensorState(state)
        DispatchQueue.main.async { self.candidateScene = self.sceneDetector.detect(state) }
        sceneStateMachine.process(state)

        if playbackStarted && lastGeneratedHr > 0 {
            let currentHr = state.heartRate
            if currentHr > 0 && abs(currentHr - lastGeneratedHr) >= Self.hrDriftThreshold {
                Self.log.debug("HR drift: \(self.lastGeneratedHr) → \(currentHr) — repriming")
                lastGeneratedHr = currentHr
                DispatchQueue.main.async { self.isAdaptingToHrDrift = true }
                bufferManager.drainAndReprime(sensorState: state, scene: currentScene)
                Task { [weak self] in
                    await self?.waitForChunks(minimum: 1)
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run { self?.isAdaptingToHrDrift = false }
                }
            }
        }
    }

    private func onSceneConfirmed(_ scene: Scene) {
        Self.log.debug("Scene confirmed: \(scene.displayName)")
        let previous = currentScene
        currentScene = scene
        bufferManager.updateScene(scene)
        sensorStateCollector.locationRepository.updateForScene(scene)
        if playbackStarted, let prev = previous, prev != scene {
            Self.log.debug("Context shift \(prev.displayName) → \(scene.displayName) — repriming")
            lastGeneratedHr = currentSensorState.heartRate
            bufferManager.drainAndReprime(sensorState: currentSensorState, scene: scene)
        }
    }

    private func waitForChunks(minimum: Int) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var sub: AnyCancellable?
            sub = bufferManager.$chunksReady
                .sink { count in
                    if count >= minimum {
                        sub?.cancel()
                        cont.resume()
                    }
                }
        }
    }

    private func subscribeChunksReady() {
        chunksSubscription = bufferManager.$chunksReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self else { return }
                guard self.playbackStarted else { return }
                if count == 0 && self.playbackState == .playing {
                    self.playbackState = .buffering
                } else if count > 0 && self.playbackState == .buffering {
                    self.playbackState = .playing
                }
            }
    }
}
