import XCTest
@testable import DailyOK

/// Offline cold launch keeps the receiver signed in.
///
/// With no signal and an expired access token, the SDK's session refresh
/// throws a URLError. That used to read as "no session", which signed a
/// receiver out and took away the I'm OK button. These cover the decision that
/// now separates "can't refresh right now" from "signed out".
final class OfflineSessionRestoreTests: XCTestCase {

    private struct ServerRejected: Error {}

    private let userId = UUID()

    private func profile(id: UUID) -> AppUser {
        AppUser(
            id: id,
            email: "receiver@example.com",
            phone: nil,
            displayName: "Grandma",
            role: .receiver,
            avatarUrl: nil,
            timezone: "America/Chicago",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            lastSeenAt: nil,
            lastBatteryLevel: nil,
            lastAppVersion: nil
        )
    }

    private var offline: Error { URLError(.notConnectedToInternet) }

    // MARK: - AuthService.isSessionUnreachable

    func testConnectivityErrorWithStoredSessionIsUnreachable() {
        XCTAssertTrue(AuthService.isSessionUnreachable(offline, hasStoredSession: true))
        XCTAssertTrue(AuthService.isSessionUnreachable(URLError(.timedOut), hasStoredSession: true))
    }

    func testConnectivityErrorWithoutStoredSessionIsSignedOut() {
        XCTAssertFalse(AuthService.isSessionUnreachable(offline, hasStoredSession: false))
    }

    func testServerRejectionIsSignedOut() {
        XCTAssertFalse(AuthService.isSessionUnreachable(ServerRejected(), hasStoredSession: true))
        XCTAssertFalse(AuthService.isSessionUnreachable(URLError(.badServerResponse), hasStoredSession: true))
    }

    // MARK: - AuthViewModel.offlineLaunchProfile

    func testOfflineWithStoredSessionAndCacheStaysSignedIn() {
        let cached = profile(id: userId)
        let restored = AuthViewModel.offlineLaunchProfile(
            for: offline,
            storedSessionUserId: userId,
            cachedProfile: { $0 == self.userId ? cached : nil }
        )
        XCTAssertEqual(restored?.id, userId)
        XCTAssertEqual(restored?.role, .receiver)
    }

    func testOfflineWithoutCachedProfileSignsOut() {
        XCTAssertNil(AuthViewModel.offlineLaunchProfile(
            for: offline,
            storedSessionUserId: userId,
            cachedProfile: { _ in nil }
        ))
    }

    func testOfflineWithoutStoredSessionSignsOut() {
        let cached = profile(id: userId)
        XCTAssertNil(AuthViewModel.offlineLaunchProfile(
            for: offline,
            storedSessionUserId: nil,
            cachedProfile: { _ in cached }
        ))
    }

    func testDefinitiveRejectionSignsOutEvenWithCache() {
        let cached = profile(id: userId)
        XCTAssertNil(AuthViewModel.offlineLaunchProfile(
            for: ServerRejected(),
            storedSessionUserId: userId,
            cachedProfile: { _ in cached }
        ))
    }

    func testCachedProfileForAnotherUserIsNotUsed() {
        let someoneElse = profile(id: UUID())
        XCTAssertNil(AuthViewModel.offlineLaunchProfile(
            for: offline,
            storedSessionUserId: userId,
            cachedProfile: { _ in someoneElse }
        ))
    }

    // MARK: - CachedProfileStore

    func testCachedProfileRoundTripsAndIsRemoved() throws {
        let suite = "OfflineSessionRestoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let user = profile(id: userId)
        CachedProfileStore.save(user, defaults: defaults)

        let loaded = try XCTUnwrap(CachedProfileStore.load(for: userId, defaults: defaults))
        XCTAssertEqual(loaded.id, user.id)
        XCTAssertEqual(loaded.displayName, user.displayName)
        XCTAssertEqual(loaded.role, user.role)
        XCTAssertEqual(loaded.timezone, user.timezone)
        XCTAssertEqual(loaded.createdAt, user.createdAt)
        XCTAssertNil(CachedProfileStore.load(for: UUID(), defaults: defaults))

        CachedProfileStore.remove(for: userId, defaults: defaults)
        XCTAssertNil(CachedProfileStore.load(for: userId, defaults: defaults))
    }
}
