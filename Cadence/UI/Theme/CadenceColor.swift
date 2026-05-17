import SwiftUI

/// Cadence color palette. Ported from `ui/theme/Color.kt`.
enum CadenceColor {
    // Brand
    static let bg          = Color(hex: 0x0B1220)
    static let surface     = Color(hex: 0x111A2E)
    static let surfaceHi   = Color(hex: 0x16213A)
    static let border      = Color.white.opacity(0.08)
    static let borderHi    = Color.white.opacity(0.14)

    static let text        = Color(hex: 0xF4F6FB)
    static let textMute    = Color(hex: 0xF4F6FB).opacity(0.62)
    static let textDim     = Color(hex: 0xF4F6FB).opacity(0.40)

    static let blue        = Color(hex: 0x4F8BFF)
    static let blueDim     = Color(hex: 0x4F8BFF).opacity(0.16)
    static let blueDimHi   = Color(hex: 0x4F8BFF).opacity(0.28)
    static let blueDeep    = Color(hex: 0x3870E6)

    static let orange      = Color(hex: 0xFF8A3D)
    static let orangeDim   = Color(hex: 0xFF8A3D).opacity(0.18)
    static let orangeDimHi = Color(hex: 0xFF8A3D).opacity(0.32)
    static let orangeDeep  = Color(hex: 0xE67630)

    static let red         = Color(hex: 0xFF5C6B)

    // Surface aliases
    static let surface0 = bg
    static let surface1 = surface
    static let surface2 = surfaceHi

    // Text tokens
    static let textPrimary   = text
    static let textSecondary = textMute
    static let textTertiary  = textDim

    // Feedback
    static let feedbackLike    = Color(hex: 0x56C96D)
    static let feedbackDislike = red
    static let feedbackNeutral = Color(hex: 0xEEEEF5).opacity(0.40)

    static let warningAmber = orange
    static let errorRed     = red

    // Scene accent tints (dark background washes)
    static func sceneTint(for scene: Scene?) -> Color {
        switch scene {
        case .running:   return Color(hex: 0x2E1A00)
        case .cycling:   return Color(hex: 0x1A2200)
        case .walking:   return Color(hex: 0x0A2010)
        case .commuting: return Color(hex: 0x081525)
        case .workout:   return Color(hex: 0x250A20)
        case .focus:     return Color(hex: 0x0A1520)
        case .party:     return Color(hex: 0x251008)
        case .resting:   return Color(hex: 0x0D0820)
        case .none:      return Color(hex: 0x0A0A10)
        }
    }

    // Glow color per scene
    static func sceneGlow(for scene: Scene?) -> Color {
        switch scene {
        case .running:   return orange
        case .cycling:   return Color(hex: 0xB2D732)
        case .walking:   return Color(hex: 0x56C96D)
        case .commuting: return blue
        case .workout:   return Color(hex: 0xE040FB)
        case .focus:     return Color(hex: 0x26C6DA)
        case .party:     return orange
        case .resting:   return Color(hex: 0x9575CD)
        case .none:      return blue
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
