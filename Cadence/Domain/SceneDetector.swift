import Foundation

final class SceneDetector {

    static let commutingSpeedThreshold: Float = 25   // km/h
    static let runningSpeedThreshold: Float = 8
    static let cyclingSpeedThreshold: Float = 4
    static let walkingSpeedThreshold: Float = 2
    static let runningHrThreshold: Int = 135
    static let workoutHrThreshold: Int = 120
    static let focusHourStart: Int = 6
    static let focusHourEnd: Int = 18
    static let partyHourStart: Int = 20
    static let partyHourEndMorning: Int = 4
    static let partyHrThreshold: Int = 75
    static let partyHrStrong: Int = 90

    func detect(_ state: SensorState) -> Scene {
        // 1. Watch-reported workout is the highest-confidence signal — a sensor on
        //    the wrist already classified the activity. Use it directly, regardless
        //    of GPS speed (handles treadmill, stationary bike, rowing, elliptical).
        if let workout = state.activeWorkoutType {
            switch workout {
            case .running, .hiit: return .running
            case .cycling: return .cycling
            case .walking: return .walking
            case .rowing, .elliptical, .other: return .workout
            }
        }

        // 2. Outdoor activity — GPS gives a reliable speed signal, prefer it.
        if state.speedKmh >= Self.commutingSpeedThreshold { return .commuting }
        if state.speedKmh >= Self.runningSpeedThreshold || state.heartRate > Self.runningHrThreshold { return .running }
        if state.speedKmh >= Self.cyclingSpeedThreshold { return .cycling }
        if state.speedKmh >= Self.walkingSpeedThreshold { return .walking }

        // 3. Indoor / stationary path — GPS is ~0, so trust CoreMotion's on-device
        //    classifier. Only treat running/cycling/walking as authoritative; the
        //    stationary/automotive verdicts add no information over the fallthrough.
        if state.speedKmh < Self.walkingSpeedThreshold, let motion = state.motionActivity {
            switch motion {
            case .running: return .running
            case .cycling: return .cycling
            case .walking: return .walking
            case .stationary, .automotive, .unknown: break
            }
        }

        if isPartyContext(state) { return .party }
        if state.heartRate > Self.workoutHrThreshold { return .workout }
        if state.hourOfDay >= Self.focusHourStart && state.hourOfDay <= Self.focusHourEnd { return .focus }
        return .resting
    }

    private func isPartyContext(_ state: SensorState) -> Bool {
        if state.hourOfDay < Self.partyHourStart && state.hourOfDay > Self.partyHourEndMorning { return false }
        if state.heartRate <= Self.partyHrThreshold { return false }
        // Weekend (Fri evening, Sat, Sun) or any night with elevated HR.
        let isWeekendWindow = state.dayOfWeek == 1 || state.dayOfWeek == 7
            || (state.dayOfWeek == 6 && state.hourOfDay >= Self.partyHourStart)
        return isWeekendWindow || state.heartRate > Self.partyHrStrong
    }
}
