import SwiftUI
import UIKit

/// Daily OK haptic vocabulary — use these names rather than `UIImpactFeedbackGenerator`
/// directly so every corner of the app speaks the same tactile language.
///
/// Principles:
/// - **selection**: tiny "tick" for navigation / list item pick / tab change
/// - **light**: button press on a secondary control
/// - **medium**: primary CTA (send invite, submit form, confirm)
/// - **success**: something completed OK (check-in sent, subscription purchased)
/// - **warning**: something needs attention (missed check-in, offline)
/// - **error**: user-visible failure (invalid code, network error)
enum DailyOKHaptics {
    /// Respect the user's "Reduce haptics" setting stored in `AppState` / defaults.
    /// When disabled, only success/warning/error still fire (those convey outcomes).
    static var nonEssentialEnabled: Bool {
        UserDefaults.standard.object(forKey: "dailyok.haptics.enabled") as? Bool ?? true
    }

    static func selection() {
        guard nonEssentialEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func light() {
        guard nonEssentialEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        guard nonEssentialEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func soft() {
        guard nonEssentialEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
