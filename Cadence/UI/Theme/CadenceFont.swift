import SwiftUI

/// Typography tokens ported from `ui/theme/Type.kt`.
/// Uses system fonts (SF Pro) — substitute with custom fonts if you ship the Inter / Space Grotesk
/// / JetBrains Mono families used on Android.
enum CadenceFont {
    // Hero
    static let displayLarge  = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let displaySmall  = Font.system(size: 22, weight: .semibold, design: .rounded)

    // Headlines
    static let headlineLarge  = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let headlineMedium = Font.system(size: 22, weight: .semibold)
    static let headlineSmall  = Font.system(size: 18, weight: .semibold)

    // Titles
    static let titleLarge  = Font.system(size: 16, weight: .semibold)
    static let titleMedium = Font.system(size: 15, weight: .medium)
    static let titleSmall  = Font.system(size: 13, weight: .medium)

    // Body
    static let bodyLarge  = Font.system(size: 15)
    static let bodyMedium = Font.system(size: 14)
    static let bodySmall  = Font.system(size: 12)

    // Labels — monospaced for telemetry-style caps
    static let labelLarge  = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let labelMedium = Font.system(size: 10.5, weight: .semibold, design: .monospaced)
    static let labelSmall  = Font.system(size: 10, weight: .medium, design: .monospaced)
}
