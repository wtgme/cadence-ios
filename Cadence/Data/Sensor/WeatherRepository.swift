import Foundation
import Combine
import OSLog

/// Open-Meteo-backed weather lookup. Same endpoint the Android client uses
/// (`api.open-meteo.com/v1/forecast`). No authentication or capability required —
/// avoids WeatherKit's paid-account entitlement requirement. Throttled to refresh on
/// movement > ~1km or every 15 min.
final class WeatherRepository: ObservableObject {

    private static let log = Logger(subsystem: "io.cadence.music", category: "WeatherRepository")

    @Published private(set) var weather: String = "Clear"

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        return URLSession(configuration: cfg)
    }()
    private var lastRefresh: Date = .distantPast
    private var lastLat: Double = 0
    private var lastLon: Double = 0

    func refresh(lat: Double, lon: Double, force: Bool = false) async {
        if lat == 0 && lon == 0 { return }

        let now = Date()
        let movedEnough = abs(lat - lastLat) > 0.01 || abs(lon - lastLon) > 0.01
        let timePassed = now.timeIntervalSince(lastRefresh) > 15 * 60
        if !force && !movedEnough && !timePassed && lastRefresh != .distantPast { return }

        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=weather_code") else {
            return
        }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Self.log.warning("Open-Meteo non-2xx response")
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = obj["current"] as? [String: Any],
                  let code = (current["weather_code"] as? NSNumber)?.intValue else {
                return
            }
            let mapped = Self.map(code: code)
            await MainActor.run { self.weather = mapped }
            lastRefresh = now
            lastLat = lat
            lastLon = lon
            Self.log.debug("Weather updated: \(mapped) (code: \(code))")
        } catch {
            Self.log.warning("Open-Meteo fetch failed: \(error.localizedDescription)")
        }
    }

    /// Mirrors the Android `mapWeatherCode`. Open-Meteo WMO codes:
    /// https://open-meteo.com/en/docs#weathervariables
    private static func map(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2, 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 61, 63, 65: return "Rainy"
        case 71, 73, 75, 77: return "Snowy"
        case 80, 81, 82: return "Rainy"
        case 85, 86: return "Snowy"
        case 95, 96, 99: return "Stormy"
        default: return "Clear"
        }
    }
}
