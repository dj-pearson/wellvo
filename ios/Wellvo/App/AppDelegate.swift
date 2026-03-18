import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
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
                print("[PushNotification] Token registration failed: \(error.localizedDescription)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
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
            handleCheckInFromNotification(userInfo: userInfo)
        case UNNotificationDefaultActionIdentifier:
            // User tapped notification body — open app
            break
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

        let checkinCategory = UNNotificationCategory(
            identifier: "CHECKIN_REQUEST",
            actions: [okAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([checkinCategory])
    }

    private func handleCheckInFromNotification(userInfo: [AnyHashable: Any]) {
        guard let requestId = userInfo["checkin_request_id"] as? String else { return }
        Task {
            do {
                try await CheckInService.shared.respondToCheckIn(requestId: requestId, source: .notification)
            } catch {
                print("[CheckIn] Notification response failed: \(error.localizedDescription)")
            }
        }
    }
}
