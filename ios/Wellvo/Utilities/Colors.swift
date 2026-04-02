import SwiftUI

/// Adaptive status colors that maintain WCAG AA contrast in both themes.
/// Note: Color assets (WellvoGreen, StatusGreenBg, etc.) are accessed via
/// Xcode's auto-generated asset symbols — no manual Color("name") needed.
extension ShapeStyle where Self == Color {
    /// Green that works on both light and dark backgrounds
    static var wellvoPrimary: Color {
        Color("WellvoGreen")
    }
}
