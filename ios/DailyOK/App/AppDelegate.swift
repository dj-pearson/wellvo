import UIKit
import UserNotifications
import os

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        // Heartbeat is started/stopped with the authenticated session lifecycle
        // (see AuthViewModel.checkSession / signOut and the scene background
        // handler) rather than unconditionally at launch, so a signed-out user
        // doesn't keep heart-beating.

        // Activate the Apple Watch session so the wrist app receives the latest
        // check-in snapshot and can report wrist check-ins back to the phone.
        PhoneWatchSync.shared.activate()

        // Observe wrist check-ins for the app lifetime. The hand-off was fully
        // wired (watch -> didReceiveWatchCheckIn) but nothing listened, so a
        // wrist check-in was invisible to the phone: its snapshot still said
        // not-checked-in (could re-escalate) and the widgets didn't update
        // (US-IOS082). On notify, optimistically mark today done (this also
        // reloads all widget timelines + re-syncs the watch) and broadcast a
        // refresh so a foregrounded receiver view reloads its status.
        NotificationCenter.default.addObserver(
            forName: PhoneWatchSync.didReceiveWatchCheckIn,
            object: nil,
            queue: .main
        ) { _ in
            SharedCheckInPublisher.markCheckedIn(at: Date())
        }

        // Sync access token to shared App Group for Notification Service Extension
        Task { await SupabaseService.shared.syncAccessTokenToExtension() }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            do {
                try await PushNotificationService.shared.registerToken(token)
            } catch {
                Log.push.error("Token registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Log.push.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Confirm delivery when notification arrives on device
        let userInfo = notification.request.content.userInfo
        if let requestId = userInfo["checkin_request_id"] as? String {
            Task {
                await CheckInService.shared.confirmDelivery(checkinRequestId: requestId)
            }
        }
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "CHECKIN_OK_ACTION":
            handleCheckInFromNotification(userInfo: userInfo, responseType: .ok)
        case "CHECKIN_NEED_HELP_ACTION":
            handleCheckInFromNotification(userInfo: userInfo, responseType: .needHelp)
        case "CHECKIN_CALL_ME_ACTION":
            handleCheckInFromNotification(userInfo: userInfo, responseType: .callMe)
        case "CHECKIN_SNOOZE_ACTION":
            handleSnoozeFromNotification(userInfo: userInfo)
        case "CALL_RECEIVER_ACTION":
            handleCallReceiver(userInfo: userInfo)
        case UNNotificationDefaultActionIdentifier:
            // User tapped notification body — open app
            // Also confirm delivery
            if let requestId = userInfo["checkin_request_id"] as? String {
                Task { await CheckInService.shared.confirmDelivery(checkinRequestId: requestId) }
            }
        default:
            break
        }

        completionHandler()
    }

    // MARK: - Private

    private func registerNotificationCategories() {
        let okAction = UNNotificationAction(
            identifier: "CHECKIN_OK_ACTION",
            title: "I'm OK ✓",
            options: [.foreground]
        )

        let needHelpAction = UNNotificationAction(
            identifier: "CHECKIN_NEED_HELP_ACTION",
            title: "I Need Help",
            options: [.foreground, .destructive]
        )

        let callMeAction = UNNotificationAction(
            identifier: "CHECKIN_CALL_ME_ACTION",
            title: "Call Me",
            options: [.foreground]
        )

        // Background snooze — defers escalation without opening the app.
        let snoozeAction = UNNotificationAction(
            identifier: "CHECKIN_SNOOZE_ACTION",
            title: "Remind me in 15 min",
            options: []
        )

        let checkinCategory = UNNotificationCategory(
            identifier: "CHECKIN_REQUEST",
            actions: [okAction, snoozeAction, needHelpAction, callMeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Urgent alert category for owners (call me / need help alerts)
        let callNowAction = UNNotificationAction(
            identifier: "CALL_RECEIVER_ACTION",
            title: "Call Now",
            options: [.foreground]
        )

        let urgentAlertCategory = UNNotificationCategory(
            identifier: "URGENT_ALERT",
            actions: [callNowAction],
            intentIdentifiers: [],
            options: []
        )

        // Location/battery alert category for owners
        let viewLocationAction = UNNotificationAction(
            identifier: "VIEW_LOCATION_ACTION",
            title: "View Details",
            options: [.foreground]
        )

        let locationAlertCategory = UNNotificationCategory(
            identifier: "LOCATION_ALERT",
            actions: [viewLocationAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            checkinCategory,
            urgentAlertCategory,
            locationAlertCategory,
        ])
    }

    private func handleCallReceiver(userInfo: [AnyHashable: Any]) {
        // Look up the receiver's phone number and initiate a call
        guard let receiverIdString = userInfo["receiver_id"] as? String,
              let receiverId = UUID(uuidString: receiverIdString) else { return }

        Task {
            // Fetch receiver's phone number
            let users: [AppUser] = try await SupabaseService.shared.client
                .from("users")
                .select("id, phone")
                .eq("id", value: receiverId.uuidString)
                .limit(1)
                .execute()
                .value

            guard let phone = users.first?.phone, !phone.isEmpty else {
                Log.general.error("No phone number found for receiver")
                return
            }

            // Normalize to tel:// URL format
            let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
            guard let telURL = URL(string: "tel://\(cleaned)") else { return }

            await MainActor.run {
                UIApplication.shared.open(telURL)
            }
        }
    }

    private func handleSnoozeFromNotification(userInfo: [AnyHashable: Any]) {
        guard let requestIdString = userInfo["checkin_request_id"] as? String,
              let requestId = UUID(uuidString: requestIdString) else { return }
        Task {
            // Defer escalation server-side (best-effort; bounded server-side).
            do {
                try await CheckInService.shared.snoozeCheckIn(requestId: requestId)
            } catch {
                Log.checkIn.error("Notification snooze failed: \(error.localizedDescription, privacy: .public)")
            }
            // Re-arm the local fallback reminder regardless, so the receiver is
            // nudged again in 15 minutes even if the snooze POST didn't land.
            await PushNotificationService.shared.scheduleLocalCheckinFallback(
                at: Date().addingTimeInterval(15 * 60),
                isKidMode: false
            )
        }
    }

    private func handleCheckInFromNotification(userInfo: [AnyHashable: Any], responseType: CheckInResponseType) {
        guard let requestId = userInfo["checkin_request_id"] as? String else { return }
        Task {
            do {
                // Get current location and battery for the check-in response
                let location = await LocationService.shared.getCurrentLocation()

                UIDevice.current.isBatteryMonitoringEnabled = true
                let batteryLevel = UIDevice.current.batteryLevel
                let battery: Double? = batteryLevel >= 0 ? Double(batteryLevel) : nil

                try await CheckInService.shared.respondToCheckIn(
                    requestId: requestId,
                    source: .notification,
                    responseType: responseType,
                    location: location,
                    batteryLevel: battery
                )
            } catch {
                Log.checkIn.error("Notification check-in response failed: \(error.localizedDescription, privacy: .public)")
                // If the device is genuinely offline, persist the check-in so it
                // syncs later instead of being lost. Only for a plain "I'm OK" —
                // urgent responses (need help / call me) must reach the server
                // live, so we don't silently defer them. Mirrors the app-button
                // path's "queue only when offline" guard to avoid duplicate
                // inserts hitting the daily unique index.
                let isOnline = await OfflineCheckInService.shared.isOnline
                if responseType == .ok, !isOnline {
                    if let family = try? await FamilyService.shared.getFamily(),
                       let session = try? await SupabaseService.shared.client.auth.session {
                        try? await OfflineCheckInService.shared.queueCheckIn(
                            familyId: family.id,
                            receiverId: session.user.id,
                            mood: nil,
                            source: .notification
                        )
                    }
                }
            }
        }
    }
}
