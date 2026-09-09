import Foundation
import Security

/// Secure Keychain wrapper for storing sensitive values like the Apple User ID.
enum KeychainService {
    private static let serviceName = "com.wellvo.ios"

    /// UserDefaults is erased when an app is deleted. The Keychain is not — that
    /// is the whole point of it, and it is also a trap. Everything this app
    /// persists securely (the Apple user id, the per-user push-token cache, and
    /// the mirrored session tokens the widget, Siri and the watch check in with)
    /// outlives a delete and is still there for whoever installs the app next.
    ///
    /// For most apps that is a footnote. Here the product is a phone handed
    /// between family members — an adult child sets one up and passes it on, a
    /// device gets inherited or resold — so "whoever installs it next" is a real
    /// person, not a hypothetical.
    private static let freshInstallSentinel = "com.wellvo.ios.hasLaunchedSinceInstall"

    /// Wipe device-persisted secrets when this is the first launch of a fresh
    /// install (US-IOS143). Cheap, synchronous, and safe to call on every launch:
    /// after the first it is a single UserDefaults read.
    ///
    /// PARTIAL by design — see US-IOS144. This clears what this app writes. The
    /// Supabase SDK keeps its own session in its own storage, and clearing that
    /// safely means first confirming what supabase-swift 2.x actually uses, which
    /// could not be verified from this environment. Until that lands, a fresh
    /// install can still restore the previous user's session, and this only
    /// closes the out-of-process surfaces.
    static func purgeIfFreshInstall() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: freshInstallSentinel) else { return }
        defaults.set(true, forKey: freshInstallSentinel)

        deleteAll()
        // The mirrored tokens are the sharpest edge: the widget, the Control
        // Center control, Siri and the watch act on them with no app UI in front
        // of them, so a stale one lets a new owner's tap check in as the previous
        // user without either of them seeing anything.
        SharedKeychain.clearTokens()
        SharedCheckInStore.clear()
    }

    /// Remove every generic-password item this app stored under its service.
    /// Deleting by service rather than by a list of keys means a key added later
    /// is covered without anyone remembering to add it here.
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first. kSecUseDataProtectionKeychain pins every
        // query to the modern data-protection keychain, consistent with
        // SharedKeychain (US-IOS108).
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
