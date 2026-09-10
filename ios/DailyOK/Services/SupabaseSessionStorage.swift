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
            return value
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
