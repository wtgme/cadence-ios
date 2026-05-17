import Testing
@testable import Cadence

struct PromptBuilderTests {

    private let builder = PromptBuilder()

    private func build(
        scene: Scene? = nil,
        speedKmh: Float = 0,
        heartRate: Int = 70,
        sleepScore: Int = 75,
        stepsToday: Int64 = 0,
        activityMinutes: Int = 0,
        caloriesBurned: Float = 0,
        hourOfDay: Int = 10,
        weather: String = "Clear",
    ) -> String {
        var s = SensorState()
        s.speedKmh = speedKmh
        s.heartRate = heartRate
        s.sleepScore = sleepScore
        s.stepsToday = stepsToday
        s.activityMinutesToday = activityMinutes
        s.caloriesBurned = caloriesBurned
        s.hourOfDay = hourOfDay
        s.weather = weather
        return builder.buildMetricsContext(state: s, scene: scene)
    }

    @Test func sceneLabelsAreCorrect() {
        #expect(build(scene: .running).contains("Running"))
        #expect(build(scene: .cycling).contains("Cycling"))
        #expect(build(scene: .walking).contains("Walking"))
        #expect(build(scene: .commuting).contains("Travelling"))
        #expect(build(scene: .workout).contains("Working Out"))
        #expect(build(scene: .focus).contains("Focus"))
        #expect(build(scene: .party).contains("Party"))
        #expect(build(scene: .resting).contains("Resting"))
        #expect(build(scene: nil).contains("Stationary"))
    }

    @Test func sleepScoreBracketsProduceCorrectLabels() {
        #expect(build(sleepScore: 80).contains("Well-rested"))
        #expect(build(sleepScore: 50).contains("Average sleep"))
        #expect(build(sleepScore: 30).contains("Poorly rested"))
    }

    @Test func zeroHeartRateShowsUnknown() {
        #expect(build(heartRate: 0).contains("unknown"))
    }

    @Test func nonZeroHeartRateShowsBpmValue() {
        let result = build(heartRate: 72)
        #expect(result.contains("72 bpm"))
        #expect(!result.contains("HR: unknown"))
    }

    @Test func timeOfDayLabelsAreCorrect() {
        #expect(build(hourOfDay: 6).contains("Early morning"))
        #expect(build(hourOfDay: 10).contains("Morning"))
        #expect(build(hourOfDay: 12).contains("Midday"))
        #expect(build(hourOfDay: 15).contains("Afternoon"))
        #expect(build(hourOfDay: 19).contains("Evening"))
        #expect(build(hourOfDay: 23).contains("Night"))
    }

    @Test func outputContainsAllExpectedFields() {
        let result = build(
            scene: .running,
            speedKmh: 10,
            heartRate: 150,
            sleepScore: 80,
            stepsToday: 5000,
            activityMinutes: 30,
            caloriesBurned: 200,
            weather: "Rainy",
        )
        #expect(result.contains("Activity:"))
        #expect(result.contains("GPS Speed:"))
        #expect(result.contains("Weather:") && result.contains("rainy"))
        #expect(result.contains("HR:"))
        #expect(result.contains("Sleep:"))
        #expect(result.contains("Time:"))
        #expect(result.contains("5000 steps"))
        #expect(result.contains("30 mins"))
        #expect(result.contains("200 kcal"))
    }
}
