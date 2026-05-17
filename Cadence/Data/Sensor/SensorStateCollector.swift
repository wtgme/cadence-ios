import Foundation
import Combine
import OSLog

/// Aggregates HealthKit + CoreLocation + WeatherKit into a single `SensorState` stream.
/// Builds the combined state on each input change instead of using Combine.CombineLatest —
/// keeps the type-checker happy and is easier to extend.
final class SensorStateCollector: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "SensorStateCollector")

    @Published private(set) var sensorState = SensorState()

    let locationRepository: LocationRepository
    let healthDataManager: HealthDataManager
    let sleepRepository: SleepRepository
    let healthExtrasRepository: HealthExtrasRepository
    let weatherRepository: WeatherRepository
    let readinessCalculator: ReadinessCalculator

    var healthDiagnostic: AnyPublisher<String?, Never> { healthDataManager.$diagnostic.eraseToAnyPublisher() }

    private var cancellables = Set<AnyCancellable>()
    private var lastEmitted: SensorState?

    init(
        locationRepository: LocationRepository,
        healthDataManager: HealthDataManager,
        sleepRepository: SleepRepository,
        healthExtrasRepository: HealthExtrasRepository,
        weatherRepository: WeatherRepository,
        readinessCalculator: ReadinessCalculator
    ) {
        self.locationRepository = locationRepository
        self.healthDataManager = healthDataManager
        self.sleepRepository = sleepRepository
        self.healthExtrasRepository = healthExtrasRepository
        self.weatherRepository = weatherRepository
        self.readinessCalculator = readinessCalculator

        // Subscribe to each input; rebuild the snapshot when any value updates.
        locationRepository.$locationData.sink { [weak self] _ in self?.rebuild() }.store(in: &cancellables)
        healthDataManager.$heartRate.sink { [weak self] _ in self?.rebuild() }.store(in: &cancellables)
        healthDataManager.$activityMinutesToday.sink { [weak self] _ in self?.rebuild() }.store(in: &cancellables)
        sleepRepository.$sleepScore.sink { [weak self] _ in self?.rebuild() }.store(in: &cancellables)
        healthExtrasRepository.$extras.sink { [weak self] _ in self?.rebuild() }.store(in: &cancellables)
        weatherRepository.$weather.sink { [weak self] _ in self?.rebuild() }.store(in: &cancellables)
    }

    private func rebuild() {
        let loc = locationRepository.locationData
        let hr = healthDataManager.heartRate
        let activity = healthDataManager.activityMinutesToday
        let sleep = sleepRepository.sleepScore
        let extras = healthExtrasRepository.extras
        let weather = weatherRepository.weather

        let hasSleep = sleep.durationHours > 0
        let readiness = readinessCalculator.compute(ReadinessCalculator.Inputs(
            sleepScore: hasSleep ? sleep.score : 0,
            hrvToday: extras.hrvRmssd,
            hrvBaseline: extras.hrvBaseline,
            restingHrToday: extras.restingHr,
            restingHrBaseline: extras.restingHrBaseline,
            yesterdayActiveKcal: extras.yesterdayActiveKcal,
            activeKcalBaseline: extras.activeKcalBaseline,
        ))

        let cal = Calendar.current
        let now = Date()

        var state = SensorState()
        state.speedKmh = loc.speedKmh
        state.heartRate = hr
        state.hourOfDay = cal.component(.hour, from: now)
        state.minuteOfHour = cal.component(.minute, from: now)
        state.dayOfWeek = cal.component(.weekday, from: now)
        state.weather = weather
        state.latitude = loc.latitude
        state.longitude = loc.longitude
        state.sleepScore = hasSleep ? sleep.score : 0
        state.sleepHours = sleep.durationHours
        state.sleepDeepPct = sleep.deepSleepPct
        state.sleepRemPct = sleep.remSleepPct
        state.activityMinutesToday = activity
        state.caloriesBurned = extras.caloriesBurned
        state.stepsToday = extras.stepsToday
        state.distanceKm = extras.distanceKm
        state.spo2 = extras.spo2
        state.bloodPressureSystolic = extras.bloodPressureSystolic
        state.bloodPressureDiastolic = extras.bloodPressureDiastolic
        state.bodyTemperature = extras.bodyTemperature
        state.floorsClimbed = extras.floorsClimbed
        state.readinessScore = readiness.score
        state.readinessBreakdown = readiness.breakdown

        // Suppress re-emission when only GPS noise changed.
        if let last = lastEmitted,
           abs(last.speedKmh - state.speedKmh) < 1.0,
           last.heartRate == state.heartRate,
           last.weather == state.weather,
           last.hourOfDay == state.hourOfDay,
           last.sleepScore == state.sleepScore,
           last.activityMinutesToday == state.activityMinutesToday,
           last.spo2 == state.spo2,
           last.stepsToday == state.stepsToday,
           last.readinessScore == state.readinessScore {
            return
        }
        lastEmitted = state
        DispatchQueue.main.async { self.sensorState = state }
    }

    func start() {
        healthDataManager.start()
        healthExtrasRepository.start()
        locationRepository.start()
        Task { await sleepRepository.refresh() }

        locationRepository.$locationData
            .debounce(for: .seconds(2), scheduler: DispatchQueue.global())
            .sink { [weak self] data in
                Task { await self?.weatherRepository.refresh(lat: data.latitude, lon: data.longitude) }
            }
            .store(in: &cancellables)
    }

    func stop() {
        healthDataManager.stop()
        healthExtrasRepository.stop()
        locationRepository.stop()
    }

    func refreshAll() async {
        await healthDataManager.refresh()
        await healthExtrasRepository.refresh()
        await sleepRepository.refresh()
        let loc = await locationRepository.currentOrLastKnown()
        await weatherRepository.refresh(lat: loc.latitude, lon: loc.longitude, force: true)
    }

    func hasHeartRatePermission() async -> Bool {
        await healthDataManager.hasHeartRatePermission()
    }
}
