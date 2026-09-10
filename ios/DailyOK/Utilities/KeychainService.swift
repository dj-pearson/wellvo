import Foundation
import Security

/// Secure Keychain wrapper for storing sensitive values like the Apple User ID.
enum KeychainService {
    /// Internal rather than private: `SupabaseSessionStorage` stores the auth
    /// session under this same service so that `deleteAll()` — which deletes by
    /// service, not by an enumerated key list — sweeps it up too (US-IOS144).
    static let serviceName = "com.wellvo.ios"

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
    /// Complete as of US-IOS144. The Supabase session is no longer an exception:
    /// `SupabaseSessionStorage` writes it under this app's own Keychain service,
    /// so `deleteAll()` below removes it along with everything else, and
    /// `purgeLegacySDKItems()` removes any copy left under the service the SDK
    /// used before that.
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
        // The SDK's own item, from before the app owned this storage. Left
        // behind, the migration in SupabaseSessionStorage.retrieve would adopt
        // the previous owner's session on first read and sign the new owner in
        // as them.
        SupabaseSessionStorage.purgeLegacySDKItems()
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
