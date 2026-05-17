import Foundation

struct PlaybackProgress: Equatable, Sendable {
    var positionMs: Int64 = 0
    var durationMs: Int64 = 0
}

enum PlaybackState: Sendable {
    case idle
    case buffering
    case playing
}
