import Foundation

/// Activity type of an in-progress or just-finished workout reported by the user's
/// watch (Apple Watch, Garmin, Fitbit, …) via HealthKit / Health Connect. When
/// present, this is the highest-confidence signal for scene classification — it
/// originates from a sensor on the wrist that the OS has already classified.
/// Mirrors the Android `ActiveWorkoutType` enum.
enum ActiveWorkoutType: String, Equatable, Sendable {
    case running
    case cycling
    case walking
    case rowing
    case elliptical
    case hiit
    case other
}
