import UserNotifications
import Foundation

/// Notification Service Extension that intercepts push notifications before display.
/// This runs even when the app is in the background or killed, allowing us to:
/// 1. Confirm delivery to the server (stops retry logic)
/// 2. Enrich notification content if needed
class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Confirm delivery to the server
        let userInfo = request.content.userInfo
        if let checkinRequestId = userInfo["checkin_request_id"] as? String {
            confirmDelivery(checkinRequestId: checkinRequestId) {
                contentHandler(bestAttemptContent)
            }
        } else {
            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Deliver whatever we have.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Delivery Confirmation

    private func confirmDelivery(checkinRequestId: String, completion: @escaping () -> Void) {
        // Read Supabase config from shared App Group UserDefaults
        // The main app writes these values on launch
        guard let defaults = UserDefaults(suiteName: "group.com.wellvo.ios"),
              let supabaseURL = defaults.string(forKey: "supabase_url"),
              !supabaseURL.isEmpty,
              let accessToken = defaults.string(forKey: "supabase_access_token"),
              !accessToken.isEmpty else {
            completion()
            return
        }

        let urlString = "\(supabaseURL)/functions/v1/confirm-delivery"
        guard let url = URL(string: urlString) else {
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let body: [String: String] = ["checkin_request_id": checkinRequestId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { _, _, _ in
            completion()
        }
        task.resume()
    }
}
