import SwiftUI

/// Accessibility helpers for Daily OK SwiftUI screens.
///
/// The goal is to give every screen a small set of drop-in modifiers so that
/// consistent a11y behavior (labels, live-region announcements, dynamic-type
/// aware layouts) is easy to apply without reinventing the wheel.
enum A11y {
    /// Dynamic type categories at or above this size should trigger compact
    /// layouts (e.g. stacking 3-across stat cards into a single column).
    static let compactLayoutThreshold: DynamicTypeSize = .xxLarge
}

extension View {
    /// Post a VoiceOver announcement when the bound value changes.
    func announce<T: Equatable>(_ value: T, message: @escaping (T) -> String?) -> some View {
        onChange(of: value) { newValue in
            if let msg = message(newValue) {
                UIAccessibility.post(notification: .announcement, argument: msg)
            }
        }
    }

    /// Apply a content-description-only label without making the view a
    /// standalone accessibility element (for icons that supplement text).
    func a11yHint(_ hint: String) -> some View {
        accessibilityHint(Text(hint))
    }
}

extension DynamicTypeSize {
    /// True when the user has selected an accessibility text size large
    /// enough that multi-column layouts should collapse to a single column.
    var useCompactLayout: Bool {
        self >= A11y.compactLayoutThreshold
    }
}
