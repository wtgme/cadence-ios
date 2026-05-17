import Foundation

/// User's current mental and physiological state as estimated by the LLM (Step 1a).
/// All numeric fields are optional — partial parse is still usable for Step 1b.
struct MentalState: Equatable, Sendable, Codable {
    /// Russell circumplex activation axis. 0 = deeply relaxed, 10 = maximally activated.
    let arousal: Int?
    /// Russell circumplex pleasure axis. -5 = very distressed, 0 = neutral, +5 = very happy.
    let valence: Int?
    /// Psychological stress. 0 = completely relaxed, 10 = extreme stress.
    let stress: Int?
    /// Subjective physical energy. 0 = exhausted, 10 = fully energised.
    let energy: Int?
    /// Attentional focus. 0 = scattered/drowsy, 10 = deep sustained concentration.
    let focus: Int?
    /// Short descriptive phrase, e.g. "alert and motivated".
    let mood: String?
    /// Full LLM response text, preserved for debug display.
    var rawLlmText: String = ""
}
