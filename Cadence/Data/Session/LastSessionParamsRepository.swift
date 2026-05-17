import Foundation

struct CachedSessionParams {
    let params: SongParams
    let mentalState: MentalState?
    let scene: Scene?
    let heartRate: Int
    let savedAtMs: Int64
}

protocol LastSessionParamsStore: AnyObject {
    func load() async -> CachedSessionParams?
    func save(params: SongParams, mentalState: MentalState?, scene: Scene?, heartRate: Int) async
    func isFreshFor(_ cached: CachedSessionParams, currentScene: Scene?, currentHr: Int) -> Bool
}

/// Persists the most recent SongParams + MentalState so a short relaunch can reuse them.
final class LastSessionParamsRepository: LastSessionParamsStore {

    static let freshTtlMs: Int64 = 10 * 60 * 1000   // 10 min
    static let hrBucketBpm = 15

    private let store: UserDefaults

    private enum Key {
        static let paramsJson      = "last_session_params_json"
        static let mentalStateJson = "last_session_mental_state_json"
        static let sceneName       = "last_session_scene"
        static let heartRate       = "last_session_heart_rate"
        static let savedAtMs       = "last_session_saved_at_ms"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
    }

    func load() async -> CachedSessionParams? {
        guard let paramsJson = store.string(forKey: Key.paramsJson)?.data(using: .utf8),
              let params = try? JSONDecoder().decode(SongParams.self, from: paramsJson)
        else { return nil }

        let mentalState: MentalState? = {
            guard let data = store.string(forKey: Key.mentalStateJson)?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(MentalState.self, from: data)
        }()
        let scene: Scene? = (store.string(forKey: Key.sceneName)).flatMap { Scene(rawValue: $0) }
        let hr = store.integer(forKey: Key.heartRate)
        let savedAt = Int64(store.double(forKey: Key.savedAtMs))

        return CachedSessionParams(
            params: params,
            mentalState: mentalState,
            scene: scene,
            heartRate: hr,
            savedAtMs: savedAt,
        )
    }

    func save(params: SongParams, mentalState: MentalState?, scene: Scene?, heartRate: Int) async {
        if let paramsData = try? JSONEncoder().encode(params),
           let paramsJson = String(data: paramsData, encoding: .utf8) {
            store.set(paramsJson, forKey: Key.paramsJson)
        }
        if let mentalState = mentalState,
           let data = try? JSONEncoder().encode(mentalState),
           let json = String(data: data, encoding: .utf8) {
            store.set(json, forKey: Key.mentalStateJson)
        } else {
            store.removeObject(forKey: Key.mentalStateJson)
        }
        if let scene = scene {
            store.set(scene.rawValue, forKey: Key.sceneName)
        } else {
            store.removeObject(forKey: Key.sceneName)
        }
        store.set(heartRate, forKey: Key.heartRate)
        store.set(Date().timeIntervalSince1970 * 1000, forKey: Key.savedAtMs)
    }

    func isFreshFor(_ cached: CachedSessionParams, currentScene: Scene?, currentHr: Int) -> Bool {
        let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.savedAtMs
        if age > Self.freshTtlMs { return false }
        if cached.scene != currentScene { return false }
        if currentHr > 0 && cached.heartRate > 0
            && abs(currentHr - cached.heartRate) >= Self.hrBucketBpm { return false }
        return true
    }
}
