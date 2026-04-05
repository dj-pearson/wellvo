import UIKit

/// Semantic haptic feedback API for Wellvo.
///
/// Callers use meaningful verbs (checkInSuccess, actionConfirm, warning, error…)
/// instead of raw UIKit generators so that the tactile language stays
/// consistent across the entire app.
///
/// iOS automatically honors the system Accessibility > Touch > Vibration
/// toggle for all `UIFeedbackGenerator` subclasses, so no manual check needed.
enum WellvoHaptics {
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)

    /// Light tick — use for selection changes (picking a mood, a location tag).
    static func selectionChanged() {
        selection.selectionChanged()
    }

    /// Single confirm tap — buttons, toggles.
    static func actionConfirm() {
        lightImpact.impactOccurred()
    }

    /// Success pattern — successful check-in, pairing complete.
    static func checkInSuccess() {
        notification.notificationOccurred(.success)
    }

    /// Warning pattern — escalation warning, low battery hint.
    static func warning() {
        notification.notificationOccurred(.warning)
    }

    /// Error pattern — failed check-in, auth failure, network error.
    static func error() {
        notification.notificationOccurred(.error)
    }

    /// Heavy thump — use sparingly for celebratory moments.
    static func celebration() {
        heavyImpact.impactOccurred()
    }

    /// Call when a view appears to reduce first-use latency.
    static func prepare() {
        notification.prepare()
        selection.prepare()
        lightImpact.prepare()
        mediumImpact.prepare()
    }
}
