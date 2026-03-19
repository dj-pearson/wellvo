import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        UIDevice.current.isBatteryMonitoringEnabled = true
        HeartbeatService.shared.start()
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

        let checkinCategory = UNNotificationCategory(
            identifier: "CHECKIN_REQUEST",
            actions: [okAction, needHelpAction, callMeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([checkinCategory])
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
                print("[CheckIn] Notification response failed: \(error.localizedDescription)")
            }
        }
    }
}
