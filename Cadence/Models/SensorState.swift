import Foundation

struct SensorState: Equatable, Sendable {
    var speedKmh: Float = 0
    var heartRate: Int = 0
    var hourOfDay: Int = 0
    var minuteOfHour: Int = 0
    /// Calendar.Component.weekday-style: 1=Sunday … 7=Saturday (matches Android Calendar.DAY_OF_WEEK).
    var dayOfWeek: Int = 1
    var weather: String = "Clear"
    var latitude: Double = 0
    var longitude: Double = 0
    var sleepScore: Int = 0
    var sleepHours: Float = 0
    var sleepDeepPct: Float = 0
    var sleepRemPct: Float = 0
    var activityMinutesToday: Int = 0
    var caloriesBurned: Float = 0
    var stepsToday: Int64 = 0
    var distanceKm: Float = 0
    var spo2: Int = 0
    var bloodPressureSystolic: Int = 0
    var bloodPressureDiastolic: Int = 0
    var bodyTemperature: Float = 0
    var floorsClimbed: Int = 0
    var readinessScore: Int = 0
    var readinessBreakdown: String = ""
    /// On-device CoreMotion classification (walking/running/cycling/stationary). Used
    /// by `SceneDetector` when GPS speed is ~0 (e.g., treadmill, stationary bike).
    var motionActivity: MotionActivity? = nil
    /// Activity type of an in-progress workout reported by a paired watch. Highest-
    /// confidence override in `SceneDetector` when present.
    var activeWorkoutType: ActiveWorkoutType? = nil
}
