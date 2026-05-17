import Foundation
import CoreLocation
import Combine
import OSLog

struct LocationData: Equatable {
    let speedKmh: Float
    let latitude: Double
    let longitude: Double

    static let empty = LocationData(speedKmh: 0, latitude: 0, longitude: 0)
}

/// Single source of truth for location. `LocationService` writes into it,
/// `SensorStateCollector` reads from it.
final class LocationRepository: NSObject, ObservableObject, CLLocationManagerDelegate {

    private static let log = Logger(subsystem: "io.cadence.music", category: "LocationRepository")

    @Published private(set) var locationData: LocationData = .empty

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var currentDesiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    private var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = currentDesiredAccuracy
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .fitness
        // Background updates require the "Location updates" background mode. Only enable
        // it when the Info.plist actually advertises the capability; otherwise the
        // assignment can crash on simulators without the capability provisioned.
        let modes = (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]) ?? []
        if modes.contains("location") {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
    }

    /// Adapt accuracy to detected scene. Active scenes (running/cycling/commuting) → best accuracy;
    /// sedentary → reduced accuracy to save battery.
    func updateForScene(_ scene: Scene?) {
        let highAccuracy: Set<Scene?> = [.running, .cycling, .commuting]
        let target: CLLocationAccuracy = highAccuracy.contains(scene)
            ? kCLLocationAccuracyBest
            : kCLLocationAccuracyHundredMeters
        if target == currentDesiredAccuracy { return }
        currentDesiredAccuracy = target
        manager.desiredAccuracy = target
        Self.log.debug("Switched GPS accuracy for scene=\(scene?.displayName ?? "nil")")
    }

    /// Cold-start fast path; returns immediately with the cached value if present.
    func currentOrLastKnown() async -> LocationData {
        if locationData.latitude != 0 || locationData.longitude != 0 { return locationData }
        if let loc = manager.location {
            let data = LocationData(speedKmh: 0, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            await MainActor.run { self.locationData = data }
            return data
        }
        return locationData
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let speedKmh = computeSpeed(loc)
        let data = LocationData(speedKmh: speedKmh, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        DispatchQueue.main.async { self.locationData = data }
        lastLocation = loc
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.log.warning("locationManager failed: \(error.localizedDescription)")
    }

    private func computeSpeed(_ location: CLLocation) -> Float {
        let gpsSpeed = max(0, Float(location.speed)) * 3.6   // m/s → km/h
        if location.speed >= 0.5 / 3.6 { return gpsSpeed }
        if let prev = lastLocation {
            let dt = location.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 0 {
                let dist = location.distance(from: prev)
                let derived = Float(dist / dt) * 3.6
                if derived < 200 { return derived }
            }
        }
        return gpsSpeed
    }
}
