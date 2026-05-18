import Foundation
import HealthKit

enum HealthKitPermissions {

    /// Apple recommends a single HKHealthStore per app; creating one per call adds
    /// noticeable setup overhead on the first auth request.
    static let sharedStore = HKHealthStore()

    /// All HealthKit types Cadence needs read access to. Mirrors the Android
    /// HEALTH_CONNECT_PERMISSIONS set. Resolved once at startup.
    static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []
        let quantityIds: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .stepCount,
            .oxygenSaturation,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
            .bodyTemperature,
            .flightsClimbed,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .appleExerciseTime,
        ]
        for id in quantityIds {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }()

    static func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        try await sharedStore.requestAuthorization(toShare: [], read: readTypes)
        return true
    }
}
