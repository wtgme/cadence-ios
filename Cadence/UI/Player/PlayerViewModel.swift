import Foundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {

    private let orchestrator: MusicOrchestrator

    @Published var currentScene: Scene?
    @Published var candidateScene: Scene?
    @Published var sensorState = SensorState()
    @Published var playbackState: PlaybackState = .idle
    @Published var chunksReady: Int = 0
    @Published var currentMetricsContext: String = ""
    @Published var currentSongParams: SongParams?
    @Published var currentMentalState: MentalState?
    @Published var lastError: String?
    @Published var songHistory: [GeneratedSong] = []
    @Published var playbackProgress = PlaybackProgress()
    @Published var hasPrevious = false
    @Published var tasteMemory = UserTasteMemory()
    @Published var currentAdjustment = UserMusicAdjustment()
    @Published var hasHealthPermissions = true
    @Published var healthDiagnostic: String?
    @Published var isAdaptingToHrDrift = false
    @Published var isRefreshingBiometrics = false
    @Published var generationStartMs: Int64 = 0

    private var cancellables = Set<AnyCancellable>()

    init(orchestrator: MusicOrchestrator = DIContainer.shared.musicOrchestrator) {
        self.orchestrator = orchestrator
        orchestrator.$currentScene.receive(on: DispatchQueue.main).assign(to: &$currentScene)
        orchestrator.$candidateScene.receive(on: DispatchQueue.main).assign(to: &$candidateScene)
        orchestrator.$currentSensorState.receive(on: DispatchQueue.main).assign(to: &$sensorState)
        orchestrator.$playbackState.receive(on: DispatchQueue.main).assign(to: &$playbackState)
        orchestrator.$hasHealthPermissions.receive(on: DispatchQueue.main).assign(to: &$hasHealthPermissions)
        orchestrator.$isAdaptingToHrDrift.receive(on: DispatchQueue.main).assign(to: &$isAdaptingToHrDrift)
        orchestrator.chunksReadyPublisher.receive(on: DispatchQueue.main).assign(to: &$chunksReady)
        orchestrator.currentMetricsContextPublisher.receive(on: DispatchQueue.main).assign(to: &$currentMetricsContext)
        orchestrator.currentSongParamsPublisher.receive(on: DispatchQueue.main).assign(to: &$currentSongParams)
        orchestrator.currentMentalStatePublisher.receive(on: DispatchQueue.main).assign(to: &$currentMentalState)
        orchestrator.lastErrorPublisher.receive(on: DispatchQueue.main).assign(to: &$lastError)
        orchestrator.songHistoryPublisher.receive(on: DispatchQueue.main).assign(to: &$songHistory)
        orchestrator.playbackProgressPublisher.receive(on: DispatchQueue.main).assign(to: &$playbackProgress)
        orchestrator.hasPreviousPublisher.receive(on: DispatchQueue.main).assign(to: &$hasPrevious)
        orchestrator.tasteMemoryPublisher.receive(on: DispatchQueue.main).assign(to: &$tasteMemory)
        orchestrator.currentAdjustmentPublisher.receive(on: DispatchQueue.main).assign(to: &$currentAdjustment)
        orchestrator.healthDiagnosticPublisher.receive(on: DispatchQueue.main).assign(to: &$healthDiagnostic)

        // Track when buffering started for the elapsed-seconds display.
        orchestrator.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .buffering {
                    // Defer to next runloop so this can't fire during a body update.
                    DispatchQueue.main.async {
                        self?.generationStartMs = Int64(Date().timeIntervalSince1970 * 1000)
                    }
                }
            }
            .store(in: &cancellables)

        orchestrator.startDetection()
        Task { await orchestrator.checkHealthPermissions() }
    }

    func startPlayback() { orchestrator.startPlayback() }
    func stop() { orchestrator.stop() }
    func overrideScene(_ scene: Scene) { orchestrator.forceScene(scene) }
    func clearSceneOverride() { orchestrator.clearSceneOverride() }
    func retryGeneration() { orchestrator.retryGeneration() }

    func thumbsUp() {
        guard let p = currentSongParams else { return }
        orchestrator.recordListenResult(params: p, listenFraction: 1.0)
    }

    func thumbsDown() {
        guard let p = currentSongParams else { return }
        orchestrator.recordListenResult(params: p, listenFraction: 0.0)
    }

    func resetTasteMemory() { orchestrator.resetTasteMemory() }
    func toggleGenre(_ g: String) { orchestrator.toggleGenre(g) }
    func clearGenres() { orchestrator.clearGenres() }
    func setEnergyBias(_ delta: Int) { orchestrator.setEnergyBias(delta) }
    func submitFreeText(_ t: String) { orchestrator.submitFreeText(t) }

    func skipToNext() {
        if let params = currentSongParams, playbackProgress.durationMs > 0 {
            let fraction = Float(playbackProgress.positionMs) / Float(playbackProgress.durationMs)
            orchestrator.recordListenResult(params: params, listenFraction: fraction)
        }
        orchestrator.skipToNext()
    }

    func skipToPrevious() { orchestrator.skipToPrevious() }
    func seek(positionMs: Int64) { orchestrator.seek(positionMs: positionMs) }

    func refreshBiometrics() {
        guard !isRefreshingBiometrics else { return }
        Task {
            isRefreshingBiometrics = true
            await orchestrator.refreshBiometrics()
            isRefreshingBiometrics = false
        }
    }
}
