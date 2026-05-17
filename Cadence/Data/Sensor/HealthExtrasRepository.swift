import Foundation
import HealthKit
import Combine
import OSLog

struct HealthExtras: Equatable {
    var spo2: Int = 0
    var bloodPressureSystolic: Int = 0
    var bloodPressureDiastolic: Int = 0
    var bodyTemperature: Float = 0
    var floorsClimbed: Int = 0
    var caloriesBurned: Float = 0
    var stepsToday: Int64 = 0
    var distanceKm: Float = 0
    // Readiness inputs
    var restingHr: Int = 0
    var restingHrBaseline: Float = 0
    var hrvRmssd: Float = 0
    var hrvBaseline: Float = 0
    var yesterdayActiveKcal: Float = 0
    var activeKcalBaseline: Float = 0
}

/// HealthKit-backed equivalent of the Android `HealthExtrasRepository`. Polls every 5 min.
final class HealthExtrasRepository: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "HealthExtrasRepository")
    static let pollIntervalSeconds: UInt64 = 300
    static let baselineDays = 14

    @Published private(set) var extras = HealthExtras()

    private let store = HKHealthStore()
    private var pollTask: Task<Void, Never>?

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.readAll()
                try? await Task.sleep(nanoseconds: Self.pollIntervalSeconds * 1_000_000_000)
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }

    func refresh() async { await readAll() }

    private func readAll() async {
        var next = extras

        next.spo2 = await Self.latestPercent(store: store, identifier: .oxygenSaturation)
        let (sys, dia) = await Self.latestBloodPressure(store: store)
        next.bloodPressureSystolic = sys
        next.bloodPressureDiastolic = dia
        next.bodyTemperature = await Self.latestQuantity(store: store, identifier: .bodyTemperature, unit: .degreeCelsius())

        let now = Date()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        // Same as Android: fall back to rolling 24h window when too close to midnight.
        let threeHoursIn = startOfDay.addingTimeInterval(3 * 3600)
        let cumulativeStart = now > threeHoursIn ? startOfDay : now.addingTimeInterval(-86_400)

        next.stepsToday = Int64(await Self.cumulativeSum(store: store, identifier: .stepCount, unit: .count(), start: cumulativeStart, end: now))
        next.distanceKm = await Self.cumulativeSum(store: store, identifier: .distanceWalkingRunning, unit: .meter(), start: cumulativeStart, end: now) / 1000
        next.caloriesBurned = await Self.cumulativeSum(store: store, identifier: .activeEnergyBurned, unit: .kilocalorie(), start: cumulativeStart, end: now)
        if next.caloriesBurned == 0 {
            // Fallback to basal-inclusive total
            next.caloriesBurned = await Self.cumulativeSum(store: store, identifier: .basalEnergyBurned, unit: .kilocalorie(), start: cumulativeStart, end: now)
        }
        next.floorsClimbed = Int(await Self.cumulativeSum(store: store, identifier: .flightsClimbed, unit: .count(), start: cumulativeStart, end: now))

        // Readiness inputs
        let baselineStart = now.addingTimeInterval(-Double(Self.baselineDays * 86_400))
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: startOfDay)!
        let yesterdayEnd = startOfDay

        let (rhrToday, rhrBaseline) = await Self.todayAndBaseline(
            store: store, identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            baselineStart: baselineStart, now: now,
        )
        next.restingHr = Int(rhrToday)
        next.restingHrBaseline = rhrBaseline

        let (hrvToday, hrvBaseline) = await Self.todayAndBaseline(
            store: store, identifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            baselineStart: baselineStart, now: now,
        )
        next.hrvRmssd = hrvToday
        next.hrvBaseline = hrvBaseline

        // Yesterday's active kcal + baseline daily mean
        let yesterdayKcal = await Self.cumulativeSum(store: store, identifier: .activeEnergyBurned, unit: .kilocalorie(), start: yesterdayStart, end: yesterdayEnd)
        let baselineTotal = await Self.cumulativeSum(store: store, identifier: .activeEnergyBurned, unit: .kilocalorie(), start: baselineStart, end: yesterdayEnd)
        next.yesterdayActiveKcal = yesterdayKcal
        next.activeKcalBaseline = baselineTotal / Float(Self.baselineDays)

        await MainActor.run { self.extras = next }
    }

    // MARK: HealthKit helpers

    private static func latestQuantity(store: HKHealthStore, identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Float {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-86_400), end: Date(), options: [])
        return await withCheckedContinuation { (cont: CheckedContinuation<Float, Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
                cont.resume(returning: Float(v))
            }
            store.execute(q)
        }
    }

    private static func latestPercent(store: HKHealthStore, identifier: HKQuantityTypeIdentifier) async -> Int {
        let v = await latestQuantity(store: store, identifier: identifier, unit: .percent())
        return Int(v * 100)
    }

    private static func latestBloodPressure(store: HKHealthStore) async -> (Int, Int) {
        guard let sys = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let dia = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else { return (0, 0) }
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-86_400), end: Date(), options: [])
        async let sysVal = withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            let q = HKSampleQuery(sampleType: sys, predicate: predicate, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .millimeterOfMercury()) ?? 0
                cont.resume(returning: Int(v))
            }
            store.execute(q)
        }
        async let diaVal = withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            let q = HKSampleQuery(sampleType: dia, predicate: predicate, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .millimeterOfMercury()) ?? 0
                cont.resume(returning: Int(v))
            }
            store.execute(q)
        }
        return (await sysVal, await diaVal)
    }

    private static func cumulativeSum(store: HKHealthStore, identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Float {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { (cont: CheckedContinuation<Float, Never>) in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let v = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                cont.resume(returning: Float(v))
            }
            store.execute(q)
        }
    }

    private static func todayAndBaseline(store: HKHealthStore, identifier: HKQuantityTypeIdentifier, unit: HKUnit, baselineStart: Date, now: Date) async -> (Float, Float) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return (0, 0) }
        let predicate = HKQuery.predicateForSamples(withStart: baselineStart, end: now, options: [])
        let samples = await withCheckedContinuation { (cont: CheckedContinuation<[HKQuantitySample], Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1000,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        guard let latest = samples.first else { return (0, 0) }
        let todayValue = Float(latest.quantity.doubleValue(for: unit))
        let history = samples.dropFirst().map { Float($0.quantity.doubleValue(for: unit)) }
        guard !history.isEmpty else { return (todayValue, 0) }
        let baseline = history.reduce(0, +) / Float(history.count)
        return (todayValue, baseline)
    }
}
