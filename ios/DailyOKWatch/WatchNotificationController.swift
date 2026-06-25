import Foundation
import UserNotifications
import WidgetKit

/// Handles the check-in reminder's action buttons on the watch. The iPhone
/// forwards the categorized `CHECKIN_REQUEST` notification to the paired watch;
/// registering the same category here makes the actions render on the wrist, and
/// this delegate completes the response via the shared check-in core — no app
/// launch and no new backend contract (it reuses process-checkin-response).
final class WatchNotificationController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationController()

    private override init() { super.init() }

    func activate() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories()
        // Coordinate with the phone's permission; harmless if already granted.
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func registerCategories() {
        let ok = UNNotificationAction(identifier: "CHECKIN_OK_ACTION", title: "I'm OK ✓", options: [.foreground])
        let needHelp = UNNotificationAction(identifier: "CHECKIN_NEED_HELP_ACTION", title: "I Need Help", options: [.destructive, .foreground])
        let callMe = UNNotificationAction(identifier: "CHECKIN_CALL_ME_ACTION", title: "Call Me", options: [.destructive, .foreground])
        let category = UNNotificationCategory(
            identifier: "CHECKIN_REQUEST",
            actions: [ok, needHelp, callMe],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // Show the reminder even if the watch app happens to be foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let responseType: String?
        switch response.actionIdentifier {
        case "CHECKIN_OK_ACTION": responseType = "ok"
        case "CHECKIN_NEED_HELP_ACTION": responseType = "need_help"
        case "CHECKIN_CALL_ME_ACTION": responseType = "call_me"
        default: responseType = nil // plain tap opens the app; nothing to send
        }

        guard let type = responseType else { completionHandler(); return }

        Task {
            do {
                try await SharedCheckInClient.checkIn(responseType: type, source: "watch")
                WidgetCenter.shared.reloadAllTimelines()
                WatchConnectivityProvider.shared.notifyPhoneOfCheckIn()
            } catch SharedCheckInError.transport {
                // Genuinely offline — queue the response (preserving its type) so
                // it still syncs later. An urgent "I Need Help" / "Call Me" must
                // never be silently dropped here (US-IOS119). Only queue on a
                // transport error: a session-expired/not-signed-in failure would
                // never flush, leaving an unflushable marker that falsely reads
                // as "saved" (US-IOS090).
                WatchOfflineQueue.enqueue(type: type)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                // sessionExpired / notSignedIn / other — don't queue; the user
                // must open the iPhone to restore the session.
            }
            completionHandler()
        }
    }
}
