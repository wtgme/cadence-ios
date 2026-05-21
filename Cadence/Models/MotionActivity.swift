import Foundation

/// On-device classification of the user's current physical activity, sourced from
/// CoreMotion's `CMMotionActivityManager`. Mirrors the Android `MotionActivity` enum.
/// Only `high`-confidence classifications should be treated as authoritative; lower
/// confidence values should fall back to GPS+HR heuristics in `SceneDetector`.
enum MotionActivity: String, Equatable, Sendable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown
}
