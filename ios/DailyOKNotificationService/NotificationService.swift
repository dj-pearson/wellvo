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
              let tokens = Self.sharedTokens(),
              !tokens.accessToken.isEmpty else {
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

        // Route through the pinned session (not URLSession.shared) so a
        // pin MISMATCH fails closed — the confirm call is never sent to an
        // un-pinned (possible MITM) host. We still deliver the notification
        // either way (US-IOS080/US-IOS086). CertificatePinning.swift is compiled
        // into this extension target.
        Task {
            defer { completion() }

            // Refresh first if the mirrored access token has expired
            // (US-IOS145). It usually HAS: Supabase access tokens last about an
            // hour, this app's whole design is one notification a day, and the
            // token is only re-mirrored when the app runs. confirm-delivery
            // requires a real user JWT and returns 401 otherwise, and the
            // response here is discarded — so a stale token meant delivery was
            // never confirmed, and the pg_cron retry job in migration 00012
            // re-sent the same reminder up to three more times at 2, 4 and 8
            // minute backoff. Four buzzes for one check-in, at the person least
            // likely to tolerate it, with nothing in any log to show for it.
            var accessToken = tokens.accessToken
            if tokens.isExpired, let refreshed = await Self.refreshTokens(tokens, defaults: defaults) {
                accessToken = refreshed.accessToken
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let body: [String: String] = ["checkin_request_id": checkinRequestId]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            _ = try? await PinnedURLSession.shared.data(for: request)
        }
    }

    /// Exchange the refresh token for a fresh session and mirror it back to the
    /// shared Keychain.
    ///
    /// Writing back is not optional: Supabase ROTATES the refresh token on use,
    /// so refreshing without persisting would invalidate the copy the main app
    /// and the widget hold and eventually sign the user out of all of them. This
    /// mirrors what SharedCheckInClient.refreshSession already does for the
    /// widget / Siri / watch path — same endpoint, same write-back.
    private static func refreshTokens(_ tokens: SharedTokens, defaults: UserDefaults) async -> SharedTokens? {
        guard let supabaseBase = defaults.string(forKey: "supabase_url"), !supabaseBase.isEmpty,
              let anonKey = defaults.string(forKey: "supabase_anon_key"), !anonKey.isEmpty,
              let url = URL(string: "\(supabaseBase)/auth/v1/token?grant_type=refresh_token") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": tokens.refreshToken])

        guard let (data, response) = try? await PinnedURLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // A sibling surface may have rotated the token out from under us.
            // Re-read rather than give up — the same reasoning as
            // SharedCheckInClient.refreshSession.
            if let reloaded = sharedTokens(), reloaded.refreshToken != tokens.refreshToken, !reloaded.isExpired {
                return reloaded
            }
            return nil
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else { return nil }

        let updated = SharedTokens(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expires_in))
        )
        saveSharedTokens(updated)
        return updated
    }

    // MARK: - Shared Keychain access

    private static let sharedKeychainService = "com.wellvo.ios.shared"
    private static let sharedKeychainAccount = "auth_tokens"

    /// The mirrored session, matching `SharedAuthTokens` field for field.
    /// Duplicated rather than imported because this extension target compiles
    /// standalone. Must stay in sync with `SharedKeychain`: service
    /// `com.wellvo.ios.shared`, account `auth_tokens`, ISO-8601 JSON.
    struct SharedTokens: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date

        /// Same 60s early margin as SharedAuthTokens.isAccessTokenExpired.
        var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
    }

    private static func sharedTokensQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sharedKeychainService,
            kSecAttrAccount as String: sharedKeychainAccount,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let group = resolveAccessGroup() {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    /// Reads the mirrored Supabase session from the shared Keychain group.
    private static func sharedTokens() -> SharedTokens? {
        var query = sharedTokensQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SharedTokens.self, from: data)
    }

    /// Mirrors a refreshed session back, so the rotated refresh token is the one
    /// every surface holds. Update-then-add, never delete-then-add: the same
    /// reasoning as SharedKeychain.set (US-IOS135) — an interrupted
    /// delete-then-add leaves every surface with no tokens at all.
    private static func saveSharedTokens(_ tokens: SharedTokens) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tokens) else { return }

        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
        let status = SecItemUpdate(sharedTokensQuery() as CFDictionary, updateAttributes as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var addQuery = sharedTokensQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessible
        SecItemAdd(addQuery as CFDictionary, nil)
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
