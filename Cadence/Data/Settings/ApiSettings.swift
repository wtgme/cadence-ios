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
        ApiSettings(
            signal2StyleBaseUrl: store.string(forKey: Key.s2sBaseUrl) ?? defaults.signal2StyleBaseUrl,
            signal2StyleApiKey:  store.string(forKey: Key.s2sApiKey)  ?? defaults.signal2StyleApiKey,
            signal2StyleModel:   store.string(forKey: Key.s2sModel)   ?? defaults.signal2StyleModel,
            songGenBaseUrl:      store.string(forKey: Key.sgBaseUrl)  ?? defaults.songGenBaseUrl,
            songGenApiKey:       store.string(forKey: Key.sgApiKey)   ?? defaults.songGenApiKey,
            songGenModel:        store.string(forKey: Key.sgModel)    ?? defaults.songGenModel,
        )
    }
}
