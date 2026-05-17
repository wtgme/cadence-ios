import Foundation
import Combine

/// 15-second debounce state machine.
/// The debounce timer runs on its own actor so it survives across publisher
/// re-subscriptions (the Android equivalent used a dedicated CoroutineScope).
final class SceneStateMachine {

    static let debounceMs: UInt64 = 15_000

    private let detector: SceneDetector
    private let subject = PassthroughSubject<Scene, Never>()
    private var pendingTask: Task<Void, Never>?
    private var lastEmittedScene: Scene?
    private var pendingCandidate: Scene?
    /// Set by `forceScene`; suppresses auto-detection changes until the user
    /// overrides again or `resetOverride` is called.
    private var userForcedScene: Scene?

    /// Stream of debounce-confirmed scenes. Replays the last emitted value to new subscribers.
    private let replay = CurrentValueSubject<Scene?, Never>(nil)
    var confirmedScenePublisher: AnyPublisher<Scene, Never> {
        replay.compactMap { $0 }.removeDuplicates().eraseToAnyPublisher()
    }

    init(detector: SceneDetector) {
        self.detector = detector
    }

    func process(_ state: SensorState) {
        let candidate = detector.detect(state)

        // Active user override — block auto-detection from reverting the scene.
        // If the sensor eventually agrees with the forced scene, lift the override
        // so normal detection can take over from here.
        if let forced = userForcedScene {
            if candidate != forced {
                pendingTask?.cancel()
                pendingCandidate = nil
                return
            } else {
                userForcedScene = nil
            }
        }

        if candidate == lastEmittedScene {
            pendingTask?.cancel()
            pendingCandidate = nil
            return
        }

        // Same candidate already waiting — let the existing timer finish
        if candidate == pendingCandidate { return }

        pendingTask?.cancel()
        pendingCandidate = candidate
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceMs * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            self.lastEmittedScene = candidate
            self.pendingCandidate = nil
            self.replay.send(candidate)
        }
    }

    func forceScene(_ scene: Scene) {
        pendingTask?.cancel()
        pendingCandidate = nil
        userForcedScene = scene
        lastEmittedScene = scene
        replay.send(scene)
    }

    /// Call when starting a fresh detection session so auto-detection resumes cleanly.
    func resetOverride() {
        userForcedScene = nil
        pendingTask?.cancel()
        pendingCandidate = nil
    }
}
