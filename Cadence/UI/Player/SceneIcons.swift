import Foundation

extension Scene {
    /// SF Symbol name for the scene.
    var iconName: String {
        switch self {
        case .running:   return "figure.run"
        case .cycling:   return "figure.outdoor.cycle"
        case .walking:   return "figure.walk"
        case .commuting: return "car.fill"
        case .workout:   return "dumbbell.fill"
        case .focus:     return "scope"
        case .party:     return "party.popper.fill"
        case .resting:   return "moon.fill"
        }
    }
}
