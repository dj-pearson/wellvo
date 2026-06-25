import AppIntents
import WidgetKit

/// The single check-in action shared across Siri, the Shortcuts app, the
/// interactive Home/Lock Screen widget, the iOS 18 Control Center control, and
/// the watch. Built once here so every surface behaves identically.
@available(iOS 16.0, watchOS 9.0, *)
struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Check In"
    static var description = IntentDescription(
        "Let your family know you're OK without opening the app."
    )

    /// We complete the check-in in the background — no need to launch the app.
    static var openAppWhenRun: Bool = false

    /// Which surface invoked this check-in ('widget' / 'control' / 'siri' /
    /// 'app'). A @Parameter so it survives the encode/decode that interactive
    /// widget buttons perform, letting analytics tell the surfaces apart
    /// (US-IOS107). Defaults to 'app' for the bare Shortcuts run.
    @Parameter(title: "Source", default: "app")
    var source: String

    init() {}
    init(source: String) { self.source = source }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            _ = try await SharedCheckInClient.checkIn(source: source)
            // Refresh every glanceable surface so the status flips to "all set".
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "You're all set — your family has been notified.")
        } catch let error as SharedCheckInError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: "Sorry, the check-in didn't go through. Please try again.")
        }
    }
}
