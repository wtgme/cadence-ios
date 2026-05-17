import Foundation

enum StreamingChunk {
    case audio(file: URL, index: Int, params: SongParams)
    case complete
    case error(message: String)
}

enum GenerationResult {
    case success(audioFile: URL, params: SongParams)
    case error(message: String)
}
