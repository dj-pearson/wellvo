import Foundation
import UserNotifications
import WatchKit
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
        Self.recordCheckInRequest(notification.request.content)
        completionHandler([.banner, .sound])
    }

    /// The family is asking (again). Recorded on the watch's snapshot so the
    /// app and complication stop saying "You're all set" for a request raised
    /// after the last check-in — an owner's "check on them now" at 3 PM left
    /// the watch showing "all set" with no button.
    static func recordCheckInRequest(_ content: UNNotificationContent) {
        guard content.categoryIdentifier == "CHECKIN_REQUEST",
              content.userInfo["checkin_request_id"] is String else { return }
        let slot = content.userInfo["slot_key"] as? String
        SharedCheckInStore.update { state in
            state.latestRequestAt = Date()
            state.latestRequestSlotKey = slot
        }
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async { WatchConnectivityProvider.shared.revision += 1 }
    }

    /// An urgent request from the wrist that didn't reach anyone. Said out
    /// loud, on the wrist, straight away — the phone's rule
    /// (presentCheckInResponseFailed(urgent: true)). It used to be queued with
    /// no word to the receiver, or dropped with an empty `catch`.
    private static func presentUrgentNotSent() {
        DispatchQueue.main.async { WKInterfaceDevice.current().play(.failure) }
        let content = UNMutableNotificationContent()
        content.title = "Your help request didn't send"
        content.body = WatchHelpCopy.notSent(ownerName: SharedCheckInStore.load()?.ownerName)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "watch-help-not-sent", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
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
            let urgent = type != "ok"
            do {
                try await SharedCheckInClient.checkIn(responseType: type, source: "watch")
                WidgetCenter.shared.reloadAllTimelines()
                WatchConnectivityProvider.shared.notifyPhoneOfCheckIn(at: Date(), type: type)
                await MainActor.run { WKInterfaceDevice.current().play(.success) }
            } catch SharedCheckInError.notInFamily {
                WatchOfflineQueue.clear()
                WidgetCenter.shared.reloadAllTimelines()
                if urgent { Self.presentUrgentNotSent() }
            } catch let error as SharedCheckInError where !urgent && (error.isQueueable || isLocked(error)) {
                // Offline, Daily OK briefly unreachable, or the iPhone's
                // biometric lock withheld the session: a plain "I'm OK" is saved
                // and sent later (with the time it was made). Only these — a
                // session-expired/not-signed-in failure would never flush,
                // leaving a marker that falsely reads as "saved" (US-IOS090).
                WatchOfflineQueue.enqueue(type: type)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                // An urgent request is never saved for silent later delivery:
                // it must reach the family now, or the receiver must know it
                // didn't so they can call. A plain "I'm OK" the server refused
                // has no phantom-success risk.
                if urgent { Self.presentUrgentNotSent() }
            }
            completionHandler()
        }
    }
}

private func isLocked(_ error: SharedCheckInError) -> Bool {
    if case .locked = error { return true }
    return false
}
