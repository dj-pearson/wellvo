import UserNotifications
import Foundation
import Security

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
        // Read the access token from the shared (encrypted) Keychain group — the
        // main app no longer mirrors it into the plaintext App Group plist. The
        // non-secret edge/supabase URLs still come from the App Group defaults.
        guard let defaults = UserDefaults(suiteName: "group.com.wellvo.ios"),
              let accessToken = Self.sharedAccessToken(),
              !accessToken.isEmpty else {
            completion()
            return
        }

        // Prefer the self-hosted edge-functions URL; fall back to supabase-hosted
        // path for backward compatibility with older app installs.
        let edgeBase = defaults.string(forKey: "edge_functions_url") ?? ""
        let supabaseBase = defaults.string(forKey: "supabase_url") ?? ""
        let urlString: String
        if !edgeBase.isEmpty {
            urlString = "\(edgeBase)/confirm-delivery"
        } else if !supabaseBase.isEmpty {
            urlString = "\(supabaseBase)/functions/v1/confirm-delivery"
        } else {
            completion()
            return
        }
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

        // Route through the pinned session (not URLSession.shared) so a
        // pin MISMATCH fails closed — the confirm call is never sent to an
        // un-pinned (possible MITM) host. We still deliver the notification
        // either way (US-IOS080/US-IOS086). CertificatePinning.swift is compiled
        // into this extension target.
        Task {
            defer { completion() }
            _ = try? await PinnedURLSession.shared.data(for: request)
        }
    }

    // MARK: - Shared Keychain access

    /// Reads the mirrored Supabase access token from the shared Keychain group.
    /// Inlined here (rather than sharing `SharedKeychain`) because this extension
    /// target compiles standalone. Must stay in sync with `SharedKeychain`:
    /// service `com.wellvo.ios.shared`, account `auth_tokens`, an ISO-8601
    /// JSON-encoded `{ accessToken, refreshToken, expiresAt }`.
    private static func sharedAccessToken() -> String? {
        let service = "com.wellvo.ios.shared"
        let account = "auth_tokens"

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = resolveAccessGroup() {
            query[kSecAttrAccessGroup as String] = group
        }

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }

        struct Tokens: Decodable { let accessToken: String }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Tokens.self, from: data))?.accessToken
    }

    private static func resolveAccessGroup() -> String? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.wellvo.ios.shared",
            kSecAttrAccount as String: "dailyok.keychain.probe",
            kSecUseDataProtectionKeychain as String: true,
        ]
        var query = base
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            var addQuery = base
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            addQuery[kSecReturnAttributes as String] = true
            status = SecItemAdd(addQuery as CFDictionary, &result)
        }
        guard status == errSecSuccess,
              let attrs = result as? [String: Any],
              let group = attrs[kSecAttrAccessGroup as String] as? String else { return nil }
        return group
    }
}
