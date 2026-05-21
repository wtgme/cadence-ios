import Foundation
import CoreMotion
import Combine
import OSLog

/// Publishes the user's current on-device-classified physical activity.
///
/// Bridges `CMMotionActivityManager.startActivityUpdates`, which fires a callback every
/// time the activity classifier changes its decision (~1 Hz when active, sparse when
/// stationary). Only `medium`+ confidence samples are surfaced — lower-confidence
/// samples publish `.unknown`, letting `SceneDetector` fall back to GPS/HR heuristics.
///
/// Mirrors the Android `MotionActivityRepository` (ActivityRecognitionClient).
final class MotionActivityRepository: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "MotionActivityRepository")

    @Published private(set) var activity: MotionActivity? = nil

    private let manager = CMMotionActivityManager()
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        guard CMMotionActivityManager.isActivityAvailable() else {
            Self.log.debug("Motion activity unavailable on this device")
            return
        }
        isRunning = true
        manager.startActivityUpdates(to: .main) { [weak self] cmActivity in
            guard let self, let cm = cmActivity else { return }
            self.publish(from: cm)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopActivityUpdates()
    }

    private func publish(from cm: CMMotionActivity) {
        // Confidence: low (0) / medium (1) / high (2). Treat low as ambiguous.
        guard cm.confidence != .low else {
            if activity != nil { activity = nil }
            return
        }
        let next: MotionActivity
        // Priority order: explicit motion modes outrank "stationary"/"unknown",
        // since a single CMMotionActivity can have multiple booleans set (e.g.,
        // walking + automotive on a moving bus).
        if cm.running { next = .running }
        else if cm.cycling { next = .cycling }
        else if cm.walking { next = .walking }
        else if cm.automotive { next = .automotive }
        else if cm.stationary { next = .stationary }
        else { next = .unknown }
        if next != activity {
            Self.log.debug("Motion → \(next.rawValue) (confidence=\(cm.confidence.rawValue))")
            activity = next
        }
    }
}
