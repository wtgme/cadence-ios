import Foundation

/// Compile-time defaults mirroring Android's BuildConfig. Override at runtime via Settings.
/// Adjust these if you wire up an .xcconfig per-environment.
enum BuildConfig {
    static let signal2StyleBaseUrl: String = "https://openrouter.ai/api/v1"
    static let signal2StyleApiKey: String = ""
    static let signal2StyleModel: String = "openrouter/free"

    static let songGenBaseUrl: String = "https://api.cadencemusics.uk/v1/music_generation"
    static let songGenApiKey: String = ""
    static let songGenModel: String = "SongGeneration-v2-large"

    static let isDebug: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
