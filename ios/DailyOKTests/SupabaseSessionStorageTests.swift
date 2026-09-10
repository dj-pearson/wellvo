import XCTest
@testable import DailyOK

/// US-IOS144. The Supabase SDK stored its session in the Keychain under its own
/// service, which survives an app delete and sat outside the fresh-install purge
/// — so a reinstall could restore the previous owner's session on a phone handed
/// between family members. The app now owns that storage.
///
/// These exercise the real Keychain. Where it is unavailable (a host app without
/// the entitlement, which is how CI builds with signing off) they skip rather
/// than fail: a Keychain test that goes red on an unrelated signing change
/// teaches everyone to ignore the suite.
final class SupabaseSessionStorageTests: XCTestCase {

    private let storage = SupabaseSessionStorage()
    private let key = "test.supabase.auth.token"

    override func setUpWithError() throws {
        try skipIfKeychainUnavailable()
        try storage.remove(key: key)
    }

    override func tearDownWithError() throws {
        try? storage.remove(key: key)
    }

    private func skipIfKeychainUnavailable() throws {
        let probe = Data("probe".utf8)
        try? storage.store(key: "test.keychain.probe", value: probe)
        let readBack = try? storage.retrieve(key: "test.keychain.probe")
        try? storage.remove(key: "test.keychain.probe")
        try XCTSkipIf(readBack != probe, "Keychain unavailable in this test host")
    }

    func testStoreThenRetrieveRoundTrips() throws {
        let session = Data(#"{"access_token":"a","refresh_token":"b"}"#.utf8)
        try storage.store(key: key, value: session)
        XCTAssertEqual(try storage.retrieve(key: key), session)
    }

    func testStoreOverwritesRatherThanDuplicating() throws {
        try storage.store(key: key, value: Data("first".utf8))
        try storage.store(key: key, value: Data("second".utf8))
        XCTAssertEqual(try storage.retrieve(key: key), Data("second".utf8))
    }

    func testRetrieveReturnsNilForAnUnknownKey() throws {
        XCTAssertNil(try storage.retrieve(key: "test.never.written"))
    }

    func testRemoveClearsTheSession() throws {
        try storage.store(key: key, value: Data("session".utf8))
        try storage.remove(key: key)
        XCTAssertNil(try storage.retrieve(key: key))
    }

    /// The shim that keeps this change from signing out every existing user on
    /// update: their session lives under the SDK's old service, and the new
    /// storage would otherwise find nothing.
    func testASessionLeftBySDKStorageIsAdoptedOnFirstRead() throws {
        let legacy = Data("legacy-session".utf8)
        try writeLegacy(legacy)

        XCTAssertEqual(try storage.retrieve(key: key), legacy)
        // Moved, not copied: a lingering old item would let the fresh-install
        // purge miss it and hand the previous owner's session to a new one.
        XCTAssertNil(readLegacy())
        // And it now lives where the purge can find it.
        XCTAssertEqual(try storage.retrieve(key: key), legacy)
    }

    func testPurgingLegacyItemsRemovesAnSDKSession() throws {
        try writeLegacy(Data("previous-owner".utf8))
        SupabaseSessionStorage.purgeLegacySDKItems()
        XCTAssertNil(readLegacy())
        XCTAssertNil(try storage.retrieve(key: key))
    }

    /// A sign-out must not leave a copy for the migration to resurrect.
    func testRemoveAlsoClearsALegacyCopy() throws {
        try writeLegacy(Data("legacy".utf8))
        try storage.remove(key: key)
        XCTAssertNil(readLegacy())
        XCTAssertNil(try storage.retrieve(key: key))
    }

    // MARK: - Direct Keychain access to the SDK's old service

    private func writeLegacy(_ value: Data) throws {
        var delete = legacyQuery()
        SecItemDelete(delete as CFDictionary)
        delete[kSecValueData as String] = value
        delete[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(delete as CFDictionary, nil)
        try XCTSkipIf(status != errSecSuccess, "Could not seed a legacy Keychain item (status \(status))")
    }

    private func readLegacy() -> Data? {
        var query = legacyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func legacyQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SupabaseSessionStorage.legacySDKService,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
