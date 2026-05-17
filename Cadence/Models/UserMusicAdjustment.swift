import Foundation

struct UserMusicAdjustment: Equatable, Sendable {
    var genreOverrides: [String] = []
    var energyBias: Int = 0
    var freeText: String? = nil

    var isEmpty: Bool {
        genreOverrides.isEmpty && energyBias == 0 && freeText == nil
    }

    func toPromptHint() -> String? {
        if isEmpty { return nil }
        var parts: [String] = []
        if !genreOverrides.isEmpty {
            parts.append("Genre: " + genreOverrides.joined(separator: ", "))
        }
        if energyBias != 0 {
            let label: String
            switch energyBias {
            case 2...:  label = "much more energetic"
            case 1:     label = "more energetic"
            case -1:    label = "calmer"
            default:    label = "much calmer"
            }
            parts.append("Energy: \(label) than default")
        }
        if let t = freeText { parts.append(t) }
        return "User preference: \(parts.joined(separator: "; ")). " +
            "Honour this unless it conflicts with the stress ≥ 7 or SpO2 safety rules."
    }
}
