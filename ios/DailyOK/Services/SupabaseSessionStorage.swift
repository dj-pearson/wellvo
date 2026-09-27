import Foundation
import Security
import Supabase

/// Keychain storage for the Supabase auth session, owned by this app rather
/// than by the SDK (US-IOS144).
///
/// ## Why this exists
///
/// `supabase-swift` 2.x defaults `AuthClient` to
/// `KeychainLocalStorage(service: "supabase.gotrue.swift")` — verified against
/// the resolved package source at v2.55.2, which is what `from: "2.0.0"`
/// resolves to, not from memory. Keychain items survive an app delete. That is
/// the whole point of the Keychain and, for this product, a trap: US-IOS143
/// wipes everything *this app* writes on the first launch after a fresh
/// install, but the SDK's own item sat outside that purge. A reinstall could
/// therefore restore the previous owner's session and sign the new owner in as
/// them — with that family's check-in history and care notes, and the ability
/// to act as them — after which the app would re-mirror those tokens to the
/// widget, Siri and the watch, undoing most of US-IOS143.
///
/// The product is a phone handed between family members. "Whoever installs it
/// next" is a real person.
///
/// ## Why an app-owned storage rather than deleting the SDK's item
///
/// Reaching into another library's Keychain items by guessed attributes breaks
/// silently the first time that library changes them — and it does change: v3
/// moves the default service to the host bundle identifier. Owning the storage
/// makes the purge deterministic and version-independent. Because the items
/// live under `KeychainService.serviceName`, the existing
/// `KeychainService.deleteAll()` — which deletes by service, not by an
/// enumerated key list — already covers them with no further coordination.
///
/// ## Accessibility
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, matching `SharedKeychain`
/// for the mirrored tokens. `ThisDeviceOnly` keeps the session out of encrypted
/// device backups, so restoring a backup onto a different phone does not carry a
/// live session with it. `AfterFirstUnlock` is required: the session is read
/// during background work (heartbeat, push handling) when the device may be
/// locked.
struct SupabaseSessionStorage: AuthLocalStorage {

    /// The service the SDK used before this app took ownership of the storage.
    /// Read once per key for the migration below, then deleted.
    static let legacySDKService = "supabase.gotrue.swift"

    func store(key: String, value: Data) throws {
        Self.write(key: key, value: value)
    }

    func retrieve(key: String) throws -> Data? {
        if let value = Self.read(key: key, service: KeychainService.serviceName) {
            return Self.reconciled(key: key, stored: value)
        }
        // One-time read-old-write-new migration. Without it, shipping this
        // change would sign out every existing user on update: their session
        // lives under the SDK's service, and the new storage would find
        // nothing. Move it across on first read, then remove the old copy so
        // the fresh-install purge has nothing left to miss.
        guard let legacy = Self.read(key: key, service: Self.legacySDKService) else {
            return nil
        }
        Self.write(key: key, value: legacy)
        Self.delete(key: key, service: Self.legacySDKService)
        return legacy
    }

    func remove(key: String) throws {
        Self.delete(key: key, service: KeychainService.serviceName)
        // A sign-out must not leave a copy behind for the migration above to
        // resurrect on the next read.
        Self.delete(key: key, service: Self.legacySDKService)
    }

    /// The SDK's session key. SupabaseService does not set `storageKey`, so
    /// `SupabaseClient` passes its own default, `sb-<first host label>-auth-token`
    /// (supabase-swift v2.55.2, SupabaseClient.swift `defaultStorageKey`) — NOT
    /// the bare AuthClient default `supabase.auth.token`, which only applies
    /// when AuthClient is built directly. Both are tried by `adopt`.
    static var sessionKeys: [String] {
        var keys: [String] = []
        if let host = URL(string: Configuration.supabaseURL)?.host,
           let ref = host.split(separator: ".").first {
            keys.append("sb-\(ref)-auth-token")
        }
        keys.append("supabase.auth.token")
        return keys
    }

    /// Adopt a newer token pair that another surface rotated.
    ///
    /// The Notification Service Extension, the widget / Control Center / Siri
    /// intent and the watch each refresh the session when their copy has
    /// expired, and Supabase rotates the refresh token on every refresh. They
    /// wrote the new pair only to the shared Keychain item, which the SDK never
    /// reads — so the app kept the old refresh token and presented it on its
    /// next refresh. GoTrue answers a spent refresh token outside its short
    /// reuse window by revoking the session: the receiver was signed out of the
    /// app, the widget and the watch together, typically the morning after a
    /// check-in push had been confirmed by the extension.
    ///
    /// Every SDK read now goes through here: when the shared item holds a pair
    /// for the same user that expires later, it is written into the stored
    /// session and returned.
    private static func reconciled(key: String, stored: Data) -> Data {
        guard let shared = SharedKeychain.loadTokens(),
              let patched = SessionTokenReconciler.adopt(shared, into: stored) else { return stored }
        write(key: key, value: patched)
        return patched
    }

    /// Adopt `tokens` (e.g. rotated on the watch and handed back) into the
    /// app's stored session directly — used when the shared item can't carry
    /// them (biometric lock withholds it). No-op unless newer, same user.
    static func adopt(_ tokens: SharedAuthTokens) {
        for key in sessionKeys {
            guard let stored = read(key: key, service: serviceName) else { continue }
            if let patched = SessionTokenReconciler.adopt(tokens, into: stored) {
                write(key: key, value: patched)
            }
            return
        }
    }

    /// Remove any session the SDK wrote under its own service.
    ///
    /// Called from the fresh-install purge. The migration in `retrieve` would
    /// otherwise happily adopt the previous owner's session on first launch,
    /// which is the exact failure this type exists to close.
    static func purgeLegacySDKItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacySDKService,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain primitives
    //
    // Data-valued, so they can't reuse KeychainService's String-valued API. Same
    // service and the same data-protection keychain, which is what lets
    // KeychainService.deleteAll() sweep these up.

    private static func write(key: String, value: Data) {
        delete(key: key, service: serviceName)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func read(key: String, service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static var serviceName: String { KeychainService.serviceName }
}

/// Pure: patch a stored Supabase session (JSON) with a newer token pair.
///
/// Works on the JSON by key so it doesn't depend on the SDK's `Session` type
/// staying source-compatible. Handles the current encoding (camelCase, which
/// supabase-swift 2.x writes with a plain JSONEncoder) and the older
/// snake_case one. Anything it doesn't recognise is returned untouched (nil).
enum SessionTokenReconciler {
    static func adopt(_ tokens: SharedAuthTokens, into stored: Data, now: Date = Date()) -> Data? {
        guard var session = (try? JSONSerialization.jsonObject(with: stored)) as? [String: Any] else { return nil }

        let accessKey = session["accessToken"] != nil ? "accessToken" : "access_token"
        let refreshKey = session["refreshToken"] != nil ? "refreshToken" : "refresh_token"
        let expiresAtKey = session["expiresAt"] != nil ? "expiresAt" : "expires_at"
        let expiresInKey = session["expiresIn"] != nil ? "expiresIn" : "expires_in"

        guard let storedAccess = session[accessKey] as? String,
              let storedRefresh = session[refreshKey] as? String,
              let storedExpiresAt = (session[expiresAtKey] as? NSNumber)?.doubleValue else { return nil }

        // Nothing to adopt: same pair, or not newer.
        guard tokens.refreshToken != storedRefresh,
              tokens.expiresAt.timeIntervalSince1970 > storedExpiresAt + 1 else { return nil }

        // Same person, or nothing. A pair for someone else (a stale item from a
        // previous sign-in) must never become this session.
        let storedUser = SharedAuthTokens.jwtSubject(storedAccess)
            ?? ((session["user"] as? [String: Any])?["id"] as? String)?.lowercased()
        guard let candidateUser = tokens.subject, let storedUser, candidateUser == storedUser else { return nil }

        session[accessKey] = tokens.accessToken
        session[refreshKey] = tokens.refreshToken
        session[expiresAtKey] = tokens.expiresAt.timeIntervalSince1970
        session[expiresInKey] = max(0, tokens.expiresAt.timeIntervalSince(now)).rounded()
        return try? JSONSerialization.data(withJSONObject: session)
    }
}
