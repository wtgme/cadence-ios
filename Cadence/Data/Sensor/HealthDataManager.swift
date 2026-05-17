import Foundation
import HealthKit
import Combine
import OSLog

/// HealthKit-backed equivalent of the Android `HealthDataManager`.
/// Polls heart rate every 3 min and exercise minutes every 6 min.
final class HealthDataManager: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "HealthDataManager")

    @Published private(set) var heartRate: Int = 0
    @Published private(set) var activityMinutesToday: Int = 0
    @Published private(set) var diagnostic: String? = nil

    private let store = HKHealthStore()
    private var pollTask: Task<Void, Never>?

    static let pollIntervalSeconds: UInt64 = 180   // 3 min
    static let slowPollEveryN: Int = 2             // sync exercise every ~6 min

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var slowTick = 0
            while !Task.isCancelled {
                await self.readHeartRate()
                if slowTick % Self.slowPollEveryN == 0 {
                    await self.readExerciseMinutes()
                }
                slowTick += 1
                try? await Task.sleep(nanoseconds: Self.pollIntervalSeconds * 1_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        await readHeartRate()
        await readExerciseMinutes()
        await MainActor.run {
            self.diagnostic = "HR: \(self.heartRate > 0 ? "\(self.heartRate) bpm" : "no data") · "
                + "Activity: \(self.activityMinutesToday) mins"
        }
    }

    func hasHeartRatePermission() async -> Bool {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return false }
        let status = store.authorizationStatus(for: type)
        // HealthKit only tells us we've asked. Probe with a query so we know whether we can read.
        if status == .notDetermined { return false }
        // status returns .sharingDenied even when read is allowed (Apple's policy). Probe:
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: Date(), options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                cont.resume(returning: error == nil)
            }
            store.execute(query)
        }
    }

    /// Latest HR in the last 60 min, falling back to 24h window.
    private func readHeartRate() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let windows: [TimeInterval] = [3600, 86_400]
        for window in windows {
            let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-window), end: Date(), options: [])
            let sample = await withCheckedContinuation { (cont: CheckedContinuation<HKQuantitySample?, Never>) in
                let q = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
                ) { _, samples, _ in
                    cont.resume(returning: samples?.first as? HKQuantitySample)
                }
                store.execute(q)
            }
            if let s = sample {
                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = Int(s.quantity.doubleValue(for: unit))
                if bpm > 0 {
                    await MainActor.run { self.heartRate = bpm }
                    return
                }
            }
        }
    }

    private func readExerciseMinutes() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let total = await withCheckedContinuation { (cont: CheckedContinuation<Double, Never>) in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .minute()) ?? 0)
            }
            store.execute(q)
        }
        await MainActor.run { self.activityMinutesToday = Int(total) }
    }
}
