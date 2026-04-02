import SwiftUI

/// Wellvo branded colors with explicit light and dark mode variants.
/// Use these instead of raw `Color.green` for consistent branding.
extension Color {
    /// Primary brand green - #22C55E in light, #86EFAC in dark for better contrast
    static let wellvoGreen = Color("WellvoGreen")

    /// Darker brand green for pressed/active states
    static let wellvoGreenDark = Color("WellvoGreenDark")

    /// Status card backgrounds with proper dark mode contrast
    static let statusGreenBg = Color("StatusGreenBg")
    static let statusYellowBg = Color("StatusYellowBg")
    static let statusRedBg = Color("StatusRedBg")
    static let statusGrayBg = Color("StatusGrayBg")
}

/// Adaptive status colors that maintain WCAG AA contrast in both themes.
extension ShapeStyle where Self == Color {
    /// Green that works on both light and dark backgrounds
    static var wellvoPrimary: Color {
        Color("WellvoGreen")
    }
}
