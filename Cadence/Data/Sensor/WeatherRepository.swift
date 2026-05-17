import Foundation
import CoreLocation
import WeatherKit
import Combine
import OSLog

/// WeatherKit-backed; throttled to refresh on movement > ~1km or every 15 min.
final class WeatherRepository: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "WeatherRepository")

    @Published private(set) var weather: String = "Clear"

    /// Lazily resolved so missing WeatherKit entitlement doesn't crash at app init.
    private lazy var service = WeatherService.shared
    private var lastRefresh: Date = .distantPast
    private var lastLat: Double = 0
    private var lastLon: Double = 0

    func refresh(lat: Double, lon: Double, force: Bool = false) async {
        if lat == 0 && lon == 0 { return }

        let now = Date()
        let movedEnough = abs(lat - lastLat) > 0.01 || abs(lon - lastLon) > 0.01
        let timePassed = now.timeIntervalSince(lastRefresh) > 15 * 60
        if !force && !movedEnough && !timePassed && lastRefresh != .distantPast { return }

        do {
            let loc = CLLocation(latitude: lat, longitude: lon)
            let current = try await service.weather(for: loc).currentWeather
            let mapped = Self.map(condition: current.condition)
            await MainActor.run { self.weather = mapped }
            lastRefresh = now
            lastLat = lat
            lastLon = lon
        } catch {
            Self.log.warning("WeatherKit fetch failed: \(error.localizedDescription)")
        }
    }

    private static func map(condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear, .hot:
            return "Clear"
        case .partlyCloudy, .cloudy, .mostlyCloudy:
            return "Cloudy"
        case .foggy, .haze, .smoky:
            return "Foggy"
        case .drizzle:
            return "Drizzle"
        case .rain, .heavyRain, .sunShowers, .freezingDrizzle, .freezingRain, .isolatedThunderstorms:
            return "Rainy"
        case .snow, .heavySnow, .blowingSnow, .blizzard, .flurries, .sleet, .wintryMix:
            return "Snowy"
        case .thunderstorms, .strongStorms, .tropicalStorm, .hurricane:
            return "Stormy"
        default:
            return "Clear"
        }
    }
}
