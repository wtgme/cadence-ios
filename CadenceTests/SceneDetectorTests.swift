import Testing
@testable import Cadence

struct SceneDetectorTests {

    private let detector = SceneDetector()

    private func state(speedKmh: Float = 0, heartRate: Int = 60, hourOfDay: Int = 10, dayOfWeek: Int = 3) -> SensorState {
        var s = SensorState()
        s.speedKmh = speedKmh
        s.heartRate = heartRate
        s.hourOfDay = hourOfDay
        s.dayOfWeek = dayOfWeek
        return s
    }

    // ── Commuting ──
    @Test func speedAtOrAboveCommutingThresholdReturnsCommuting() {
        #expect(detector.detect(state(speedKmh: 25)) == .commuting)
        #expect(detector.detect(state(speedKmh: 60)) == .commuting)
        #expect(detector.detect(state(speedKmh: SceneDetector.commutingSpeedThreshold)) == .commuting)
    }

    // ── Running ──
    @Test func speedInRunningRangeReturnsRunning() {
        #expect(detector.detect(state(speedKmh: 8)) == .running)
        #expect(detector.detect(state(speedKmh: 15)) == .running)
    }

    @Test func highHrAloneReturnsRunning() {
        #expect(detector.detect(state(speedKmh: 0, heartRate: 136)) == .running)
        #expect(detector.detect(state(speedKmh: 0, heartRate: 180)) == .running)
    }

    @Test func hrAtThresholdBoundaryDoesNotTriggerRunning() {
        // HR exactly at 135 is NOT > 135, so falls to WORKOUT (135 > 120)
        #expect(detector.detect(state(speedKmh: 0, heartRate: SceneDetector.runningHrThreshold, hourOfDay: 10)) == .workout)
    }

    // ── Cycling ──
    @Test func cyclingSpeedWithNormalHrReturnsCycling() {
        #expect(detector.detect(state(speedKmh: 4, heartRate: 90)) == .cycling)
        #expect(detector.detect(state(speedKmh: 7, heartRate: 80)) == .cycling)
    }

    // ── Walking ──
    @Test func walkingSpeedReturnsWalking() {
        #expect(detector.detect(state(speedKmh: 2)) == .walking)
        #expect(detector.detect(state(speedKmh: 3)) == .walking)
    }

    // ── Workout ──
    @Test func stationaryWithElevatedHrReturnsWorkout() {
        #expect(detector.detect(state(speedKmh: 0, heartRate: 121)) == .workout)
        #expect(detector.detect(state(speedKmh: 0, heartRate: 130)) == .workout)
    }

    @Test func hrAtWorkoutThresholdBoundaryDoesNotTriggerWorkout() {
        #expect(detector.detect(state(speedKmh: 0, heartRate: SceneDetector.workoutHrThreshold, hourOfDay: 10)) == .focus)
    }

    // ── Focus ──
    @Test func stationaryNormalHrDuringDaytimeReturnsFocus() {
        #expect(detector.detect(state(speedKmh: 0, heartRate: 65, hourOfDay: 9))  == .focus)
        #expect(detector.detect(state(speedKmh: 0, heartRate: 65, hourOfDay: 14)) == .focus)
        #expect(detector.detect(state(speedKmh: 0, heartRate: 65, hourOfDay: 18)) == .focus)
    }

    // ── Party ──
    @Test func weekendEveningWithElevatedHrReturnsParty() {
        #expect(detector.detect(state(heartRate: 85, hourOfDay: 22, dayOfWeek: 7)) == .party)
        #expect(detector.detect(state(heartRate: 80, hourOfDay: 21, dayOfWeek: 6)) == .party)
        #expect(detector.detect(state(heartRate: 90, hourOfDay: 23, dayOfWeek: 1)) == .party)
    }

    @Test func weekdayNightWithStrongHrReturnsParty() {
        #expect(detector.detect(state(heartRate: 95, hourOfDay: 22, dayOfWeek: 3)) == .party)
    }

    @Test func weekdayNightWithLowHrDoesNotReturnParty() {
        #expect(detector.detect(state(heartRate: 65, hourOfDay: 22, dayOfWeek: 3)) == .resting)
    }

    @Test func daytimeDoesNotReturnPartyEvenOnWeekend() {
        #expect(detector.detect(state(heartRate: 85, hourOfDay: 14, dayOfWeek: 7)) == .focus)
    }

    @Test func highSpeedAtNightReturnsCommutingNotParty() {
        #expect(detector.detect(state(speedKmh: 30, heartRate: 85, hourOfDay: 22, dayOfWeek: 7)) == .commuting)
    }

    // ── Resting ──
    @Test func stationaryNormalHrOutsideFocusHoursReturnsResting() {
        #expect(detector.detect(state(speedKmh: 0, heartRate: 60, hourOfDay: 22)) == .resting)
        #expect(detector.detect(state(speedKmh: 0, heartRate: 60, hourOfDay: 3))  == .resting)
        #expect(detector.detect(state(speedKmh: 0, heartRate: 60, hourOfDay: 19)) == .resting)
    }
}
