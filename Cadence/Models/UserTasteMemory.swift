import Foundation

/// Persistent taste profile accumulated across listening sessions.
/// Scores are exponential moving averages in [-1, +1]:
///   +1 = strongly preferred, -1 = strongly disliked, 0 = neutral / no data yet.
struct UserTasteMemory: Equatable, Sendable, Codable {
    /// Genre-level preferences, e.g. "electronic" → +0.72
    var genreScores: [String: Float] = [:]
    /// All tag preferences (genre + emotion + instrument)
    var tagScores: [String: Float] = [:]
    /// Scene-scoped genre preferences, key = "SCENE_NAME:genre"
    var contextGenreScores: [String: Float] = [:]
    /// Total feedback signals recorded across all sessions
    var feedbackCount: Int = 0
    /// Epoch-ms of the most recent update
    var lastUpdatedMs: Int64 = 0
}
