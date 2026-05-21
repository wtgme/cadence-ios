import Foundation
import HealthKit
import Combine
import OSLog

/// Publishes the activity type of any in-progress or just-finished workout reported
/// to HealthKit by a paired watch. When a user starts a "Running" workout on Apple
/// Watch (or Garmin/Fitbit via their bridge apps), the resulting `HKWorkout` sample
/// lands in HealthKit on save; we surface its `workoutActivityType` so that
/// `SceneDetector` can prefer it over GPS/HR heuristics.
///
/// Mirrors the Android `WorkoutSessionRepository` (Health Connect ExerciseSessionRecord).
final class WorkoutSessionRepository: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "WorkoutSessionRepository")

    /// A finished workout that ended more than this many seconds ago is no longer
    /// surfaced — by then the user has likely moved on to a different activity.
    private static let recentWorkoutWindowSeconds: TimeInterval = 5 * 60

    @Published private(set) var activeType: ActiveWorkoutType? = nil

    private let store = HKHealthStore()
    private var observer: HKObserverQuery?
    private var refreshTask: Task<Void, Never>?

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKObjectType.workoutType()

        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
            if let error = error {
                Self.log.warning("Workout observer error: \(error.localizedDescription)")
            }
            Task { await self?.refresh() }
            completion()
        }
        store.execute(query)
        observer = query

        // Background delivery so we get notified even when the user is mid-run
        // and the app has dropped into the suspended background tier.
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, error in
            if let error = error {
                Self.log.debug("enableBackgroundDelivery failed: \(error.localizedDescription)")
            }
        }

        // Periodic re-check (every 60s) — observer queries can be coalesced and we
        // want to drop the activeType back to nil once the recent-window expires.
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func stop() {
        if let observer { store.stop(observer) }
        observer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        let workout = await mostRecentWorkout()
        let now = Date()
        let mapped: ActiveWorkoutType? = {
            guard let w = workout else { return nil }
            // Treat as active if the workout is still in progress OR ended very recently.
            let endsInFuture = w.endDate > now
            let endedRecently = now.timeIntervalSince(w.endDate) <= Self.recentWorkoutWindowSeconds
            guard endsInFuture || endedRecently else { return nil }
            return Self.map(w.workoutActivityType)
        }()
        if mapped != activeType {
            Self.log.debug("Workout → \(mapped?.rawValue ?? "none")")
            await MainActor.run { self.activeType = mapped }
        }
    }

    private func mostRecentWorkout() async -> HKWorkout? {
        await withCheckedContinuation { (cont: CheckedContinuation<HKWorkout?, Never>) in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(q)
        }
    }

    private static func map(_ t: HKWorkoutActivityType) -> ActiveWorkoutType {
        switch t {
        case .running, .trackAndField: return .running
        case .cycling, .handCycling: return .cycling
        case .walking, .hiking: return .walking
        case .rowing, .paddleSports: return .rowing
        case .elliptical, .stairClimbing, .stairs, .stepTraining: return .elliptical
        case .highIntensityIntervalTraining, .crossTraining, .mixedCardio, .jumpRope:
            return .hiit
        default: return .other
        }
    }
}
