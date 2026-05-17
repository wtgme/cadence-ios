import Foundation

/// Parameters for the SongGeneration `/generate` endpoint.
/// Mirrors the Android `SongParams` Moshi class — keys use the server's snake_case.
struct SongParams: Equatable, Sendable, Codable {
    let lyric: String
    let descriptions: String?
    let autoPromptAudioType: String?
    let generateType: String

    init(lyric: String, descriptions: String? = nil, autoPromptAudioType: String? = nil, generateType: String = "bgm") {
        self.lyric = lyric
        self.descriptions = descriptions
        self.autoPromptAudioType = autoPromptAudioType
        self.generateType = generateType
    }

    enum CodingKeys: String, CodingKey {
        case lyric
        case descriptions
        case autoPromptAudioType = "auto_prompt_audio_type"
        case generateType = "generate_type"
    }
}
