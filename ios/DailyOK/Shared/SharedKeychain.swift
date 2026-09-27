import Foundation
import Security

/// The Supabase session secrets (access + refresh token and the access-token
/// expiry) mirrored to out-of-process surfaces. Kept *out* of the App Group
/// `UserDefaults` plist — which is plaintext and lands in device backups — and
/// stored only in the encrypted Keychain via `SharedKeychain`.
struct SharedAuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    /// Absolute expiry of `accessToken`.
    var expiresAt: Date

    /// True when the access token is at/near expiry (refresh 60s early).
    var isAccessTokenExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }

    /// The user the access token was issued to (the JWT `sub` claim), read
    /// without verifying the signature — used only to make sure two token
    /// pairs belong to the same person before one replaces the other.
    var subject: String? { Self.jwtSubject(accessToken) }

    static func jwtSubject(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = object["sub"] as? String, !sub.isEmpty else { return nil }
        return sub.lowercased()
    }

    /// Whether `candidate` should overwrite `existing`.
    ///
    /// Supabase rotates the refresh token on every use, and the app, the
    /// Notification Service Extension, the widget / Control Center / Siri
    /// intent and the watch can each refresh. A surface that writes an OLDER
    /// pair over a newer one hands every other surface a refresh token that
    /// has already been spent — and GoTrue's reuse detection answers a spent
    /// token by revoking the whole session, signing the receiver out of the
    /// app, the widget and the watch at once.
    ///
    /// So a pair for the same person with a later expiry is never replaced by
    /// one with an earlier expiry. Anything else (nothing stored, a different
    /// person, the same refresh token, or a newer candidate) is written.
    static func shouldReplace(existing: SharedAuthTokens?, with candidate: SharedAuthTokens) -> Bool {
        guard let existing else { return true }
        guard existing.refreshToken != candidate.refreshToken else { return true }
        guard let a = existing.subject, let b = candidate.subject, a == b else { return true }
        return candidate.expiresAt >= existing.expiresAt
    }
}

/// Keychain-backed store for the mirrored Supabase session, shared between the
/// main app and the same-device extensions (Notification Service Extension,
/// widget / Control Center control / App Intents) via a Keychain access group.
///
/// Why Keychain and not the App Group `UserDefaults`: the access/refresh tokens
/// are long-lived bearer credentials. In `UserDefaults` they sit in a plaintext
/// plist inside the group container — extractable from an unencrypted backup or
/// a jailbroken/lost device — which would nullify the deliberate
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` protection we apply here.
///
/// The watch is a *separate device*; it does not share this Keychain. It
/// receives the tokens over the encrypted WatchConnectivity channel and stores
/// them in its own (device-local) Keychain via this same type.
enum SharedKeychain {
    private static let service = "com.wellvo.ios.shared"
    private static let tokensAccount = "auth_tokens"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Access group resolution

    /// The Keychain access group shared between the app and its same-device
    /// extensions. Resolved at runtime (the team-id prefix isn't known at
    /// compile time) by reading back the access group the system assigns to an
    /// item created without an explicit group — which is the first entry in the
    /// target's `keychain-access-groups` entitlement.
    ///
    /// Falls back to `nil` (the app's default group) when the entitlement is
    /// absent, e.g. a target that doesn't share the group. Reads/writes still
    /// work within that process; only cross-process sharing is unavailable.
    static let accessGroup: String? = resolveAccessGroup()

    private static func resolveAccessGroup() -> String? {
        let probeAccount = "dailyok.keychain.probe"
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: probeAccount,
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
              let group = attrs[kSecAttrAccessGroup as String] as? String else {
            return nil
        }
        return group
    }

    // MARK: - Tokens

    @discardableResult
    static func saveTokens(_ tokens: SharedAuthTokens) -> Bool {
        guard let data = try? encoder.encode(tokens) else { return false }
        return set(account: tokensAccount, data: data)
    }

    /// Save `tokens` unless the Keychain already holds a NEWER pair for the
    /// same person (see `SharedAuthTokens.shouldReplace`). Returns whether it
    /// wrote. Use this for every write whose tokens came from somewhere other
    /// than a refresh this process just made.
    @discardableResult
    static func saveTokensIfNotOlder(_ tokens: SharedAuthTokens) -> Bool {
        guard SharedAuthTokens.shouldReplace(existing: loadTokens(), with: tokens) else { return false }
        return saveTokens(tokens)
    }

    static func loadTokens() -> SharedAuthTokens? {
        guard let data = get(account: tokensAccount) else { return nil }
        return try? decoder.decode(SharedAuthTokens.self, from: data)
    }

    static func clearTokens() {
        delete(account: tokensAccount)
    }

    // MARK: - Generic item helpers

    private static func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    @discardableResult
    private static func set(account: String, data: Data) -> Bool {
        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        // Prefer an in-place update so there is never a window with NO item: the
        // previous delete-then-add could, if interrupted between the two calls,
        // leave the surface with no tokens (silently degrading to signed-out)
        // until the next phone sync (US-IOS135).
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
        let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                         updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        func add() -> Bool {
            var addQuery = baseQuery(account: account)
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = accessible
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        if updateStatus == errSecItemNotFound { return add() }

        // Unexpected status (e.g. a legacy item with mismatched attributes):
        // self-heal by deleting and re-adding.
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        return add()
    }

    private static func get(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
