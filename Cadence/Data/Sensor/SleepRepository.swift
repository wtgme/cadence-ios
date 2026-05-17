import Foundation
import HealthKit
import Combine
import OSLog

struct SleepScore: Equatable {
    let score: Int           // 0..100
    let durationHours: Float
    let deepSleepPct: Float
    let remSleepPct: Float
}

/// Sleep quality score from HealthKit's `HKCategoryTypeIdentifierSleepAnalysis`.
final class SleepRepository: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "SleepRepository")

    @Published private(set) var sleepScore = SleepScore(
        score: 75, durationHours: 0, deepSleepPct: 0, remSleepPct: 0,
    )

    private let store = HKHealthStore()

    func refresh() async {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let end = Date()
        let start = end.addingTimeInterval(-172_800) // 48h
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let samples = await withCheckedContinuation { (cont: CheckedContinuation<[HKCategorySample], Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 200,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        if samples.isEmpty { return }

        // Treat one "session" as samples sharing a contiguous window.
        // For simplicity, group all asleep-* samples from the latest session window.
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }
        if asleep.isEmpty { return }

        let sessionEnd = asleep.first!.endDate
        let sessionStart = asleep.last!.startDate

        let totalMs = Float(sessionEnd.timeIntervalSince(sessionStart) * 1000)
        let durationHours = totalMs / 3_600_000

        var deepMs: Double = 0
        var remMs: Double = 0
        for s in asleep {
            let ms = s.endDate.timeIntervalSince(s.startDate) * 1000
            switch s.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deepMs += ms
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:  remMs  += ms
            default: break
            }
        }
        let deepPct = totalMs > 0 ? Float(deepMs) / totalMs * 100 : 0
        let remPct  = totalMs > 0 ? Float(remMs)  / totalMs * 100 : 0

        let durationScore = min(40, Int(durationHours / 7 * 40))
        let deepScore     = min(30, Int(deepPct / 20 * 30))
        let remScore      = min(30, Int(remPct  / 20 * 30))
        let total = durationScore + deepScore + remScore

        let score = SleepScore(score: total, durationHours: durationHours, deepSleepPct: deepPct, remSleepPct: remPct)
        await MainActor.run { self.sleepScore = score }
    }
}
