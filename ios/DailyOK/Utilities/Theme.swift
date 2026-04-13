import SwiftUI

/// Daily OK design tokens — colors, elevation, motion.
///
/// This is the single source of truth for the app's visual language. Every
/// screen should prefer these tokens to hardcoded values so that the premium
/// feel stays consistent and changes propagate everywhere.
enum DailyOKColor {
    // MARK: Brand green tonal ramp
    static let green50  = Color(red: 0.941, green: 0.992, blue: 0.957) // #F0FDF4
    static let green100 = Color(red: 0.863, green: 0.988, blue: 0.906) // #DCFCE7
    static let green200 = Color(red: 0.733, green: 0.969, blue: 0.816) // #BBF7D0
    static let green300 = Color(red: 0.525, green: 0.937, blue: 0.675) // #86EFAC
    static let green400 = Color(red: 0.290, green: 0.871, blue: 0.502) // #4ADE80
    static let green500 = Color(red: 0.133, green: 0.773, blue: 0.369) // #22C55E — primary brand
    static let green600 = Color(red: 0.086, green: 0.639, blue: 0.290) // #16A34A
    static let green700 = Color(red: 0.082, green: 0.502, blue: 0.239) // #15803D
    static let green800 = Color(red: 0.086, green: 0.396, blue: 0.204) // #166534
    static let green900 = Color(red: 0.078, green: 0.325, blue: 0.176) // #14532D

    /// Primary brand color, resolves to green500.
    static let brand = green500

    // MARK: Premium accents
    static let teal = Color(red: 0.078, green: 0.722, blue: 0.651)       // #14B8A6
    static let gold = Color(red: 0.961, green: 0.620, blue: 0.043)       // #F59E0B — paid features
    static let goldLight = Color(red: 0.992, green: 0.906, blue: 0.541)  // #FDE68A
    static let indigo = Color(red: 0.388, green: 0.400, blue: 0.945)     // #6366F1

    // MARK: Tonal surfaces (light)
    static let surfaceLight = Color.white
    static let surfaceLightLow = Color(red: 0.976, green: 0.980, blue: 0.984)   // #F9FAFB
    static let surfaceLightMed = Color(red: 0.953, green: 0.957, blue: 0.961)   // #F3F4F6
    static let surfaceLightHigh = Color(red: 0.898, green: 0.906, blue: 0.922)  // #E5E7EB

    // MARK: Tonal surfaces (dark) — subtly tinted toward brand green
    static let surfaceDark = Color(red: 0.043, green: 0.078, blue: 0.063)       // #0B1410
    static let surfaceDarkLow = Color(red: 0.059, green: 0.102, blue: 0.078)    // #0F1A14
    static let surfaceDarkMed = Color(red: 0.078, green: 0.133, blue: 0.098)    // #142219
    static let surfaceDarkHigh = Color(red: 0.106, green: 0.173, blue: 0.133)   // #1B2C22

    // MARK: Semantic
    static let error = Color(red: 0.937, green: 0.267, blue: 0.267)   // #EF4444
    static let warning = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B
    static let info = Color(red: 0.231, green: 0.510, blue: 0.965)    // #3B82F6
}

/// Motion tokens — durations and spring responses for consistent feel.
enum DailyOKMotion {
    static let durationInstant: Double = 0.05
    static let durationShort: Double = 0.15
    static let durationMedium: Double = 0.25
    static let durationLong: Double = 0.40
    static let durationExtraLong: Double = 0.60

    /// Standard spring for card appearance and tab transitions.
    static let smoothSpring: Animation = .spring(response: 0.45, dampingFraction: 0.85)

    /// Bouncy spring for check-in button press and success reveals.
    static let bouncySpring: Animation = .spring(response: 0.35, dampingFraction: 0.6)

    /// Linear easing for shimmer / progress loops.
    static let linear: Animation = .linear(duration: durationExtraLong * 2)
}

/// Elevation tokens — pair with SwiftUI `.shadow(...)`.
enum DailyOKElevation {
    static let level0: CGFloat = 0
    static let level1: CGFloat = 2
    static let level2: CGFloat = 6
    static let level3: CGFloat = 12
    static let level4: CGFloat = 18
    static let level5: CGFloat = 24
}

extension View {
    /// Apply a Daily OK elevation shadow consistent with the design system.
    func dailyokShadow(_ level: CGFloat, opacity: Double = 0.08) -> some View {
        shadow(
            color: Color.black.opacity(opacity),
            radius: level,
            x: 0,
            y: level * 0.4
        )
    }
}
