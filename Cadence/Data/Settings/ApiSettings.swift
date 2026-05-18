import Foundation
import Combine

struct ApiSettings: Equatable, Codable {
    var signal2StyleBaseUrl: String
    var signal2StyleApiKey: String
    var signal2StyleModel: String
    var songGenBaseUrl: String
    var songGenApiKey: String
    var songGenModel: String
}

/// Persists user-configurable API endpoints in UserDefaults. Defaults come from `BuildConfig`.
final class ApiSettingsRepository: ObservableObject {

    let defaults = ApiSettings(
        signal2StyleBaseUrl: BuildConfig.signal2StyleBaseUrl,
        signal2StyleApiKey:  BuildConfig.signal2StyleApiKey,
        signal2StyleModel:   BuildConfig.signal2StyleModel,
        songGenBaseUrl:      BuildConfig.songGenBaseUrl,
        songGenApiKey:       BuildConfig.songGenApiKey,
        songGenModel:        BuildConfig.songGenModel,
    )

    @Published private(set) var settings: ApiSettings

    private let store: UserDefaults

    private enum Key {
        static let s2sBaseUrl = "signal2style_base_url"
        static let s2sApiKey  = "signal2style_api_key"
        static let s2sModel   = "signal2style_model"
        static let sgBaseUrl  = "songgen_base_url"
        static let sgApiKey   = "songgen_api_key"
        static let sgModel    = "songgen_model"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        self.settings = Self.load(store: store, defaults: defaults)
    }

    var current: ApiSettings { settings }

    func save(_ s: ApiSettings) {
        store.set(s.signal2StyleBaseUrl, forKey: Key.s2sBaseUrl)
        store.set(s.signal2StyleApiKey,  forKey: Key.s2sApiKey)
        store.set(s.signal2StyleModel,   forKey: Key.s2sModel)
        store.set(s.songGenBaseUrl,      forKey: Key.sgBaseUrl)
        store.set(s.songGenApiKey,       forKey: Key.sgApiKey)
        store.set(s.songGenModel,        forKey: Key.sgModel)
        settings = s
    }

    func resetAll() {
        for key in [Key.s2sBaseUrl, Key.s2sApiKey, Key.s2sModel,
                    Key.sgBaseUrl, Key.sgApiKey, Key.sgModel] {
            store.removeObject(forKey: key)
        }
        settings = defaults
    }

    private static func load(store: UserDefaults, defaults: ApiSettings) -> ApiSettings {
        // Empty stored strings (e.g. from a previous install whose BuildConfig defaults
        // were blank, persisted unchanged through onboarding) are treated as "unset"
        // so the current BuildConfig defaults take effect on the next launch.
        func read(_ key: String, fallback: String) -> String {
            let stored = store.string(forKey: key)
            if let s = stored, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
            return fallback
        }
        return ApiSettings(
            signal2StyleBaseUrl: read(Key.s2sBaseUrl, fallback: defaults.signal2StyleBaseUrl),
            signal2StyleApiKey:  read(Key.s2sApiKey,  fallback: defaults.signal2StyleApiKey),
            signal2StyleModel:   read(Key.s2sModel,   fallback: defaults.signal2StyleModel),
            songGenBaseUrl:      read(Key.sgBaseUrl,  fallback: defaults.songGenBaseUrl),
            songGenApiKey:       read(Key.sgApiKey,   fallback: defaults.songGenApiKey),
            songGenModel:        read(Key.sgModel,    fallback: defaults.songGenModel),
        )
    }
}
