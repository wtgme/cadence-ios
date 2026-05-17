import Foundation

enum Scene: String, CaseIterable, Codable, Sendable, Hashable {
    case running   = "RUNNING"
    case cycling   = "CYCLING"
    case walking   = "WALKING"
    case commuting = "COMMUTING"
    case workout   = "WORKOUT"
    case focus     = "FOCUS"
    case party     = "PARTY"
    case resting   = "RESTING"

    var displayName: String {
        switch self {
        case .running:   return "Running"
        case .cycling:   return "Cycling"
        case .walking:   return "Walking"
        case .commuting: return "Commuting"
        case .workout:   return "Working Out"
        case .focus:     return "Focus"
        case .party:     return "Party"
        case .resting:   return "Resting"
        }
    }
}
