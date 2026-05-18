import Foundation

/// Compile-time defaults — mirror `cadence/local.properties` from the Android build.
/// Users can override any field at runtime via Settings → API Settings; their values
/// persist in `UserDefaults` and take precedence over these defaults on every load.
enum BuildConfig {
    static let signal2StyleBaseUrl: String = "https://chat.cadencemusics.uk/v1"
    static let signal2StyleApiKey: String = "dummy"
    static let signal2StyleModel: String = "google/gemma-4-E4B-it"

    static let songGenBaseUrl: String = "https://api.cadencemusics.uk/v1/music_generation"
    static let songGenApiKey: String = "dummy"
    static let songGenModel: String = "SongGeneration-v2-large"

    static let isDebug: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
