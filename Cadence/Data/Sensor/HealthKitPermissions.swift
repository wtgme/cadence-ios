import Foundation
import HealthKit

enum HealthKitPermissions {

    /// All HealthKit types Cadence needs read access to. Mirrors the Android HEALTH_CONNECT_PERMISSIONS set.
    static var readTypes: Set<HKObjectType> {
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
    }

    static func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let store = HKHealthStore()
        try await store.requestAuthorization(toShare: [], read: readTypes)
        return true
    }
}
