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

/// Refresh-token split-brain: an extension rotated the refresh token, and the
/// app must adopt the rotated pair rather than later present the consumed one.
/// These cover the decision of whether the shared pair is the newer session.
final class SharedSessionReconcileTests: XCTestCase {

    private let userId = UUID()
    private let sdkIssuedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private var sdkExpiresAt: Date { sdkIssuedAt.addingTimeInterval(3600) }

    /// An unsigned JWT carrying only `sub`, base64url-encoded without padding.
    private func jwt(sub: String) -> String {
        func b64url(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(b64url(#"{"alg":"HS256"}"#)).\(b64url("{\"sub\":\"\(sub)\"}")).sig"
    }

    private func shared(
        refresh: String = "rotated",
        sub: String? = nil,
        issuedAfter: TimeInterval? = 1800,
        expiresAfter: TimeInterval = 5400
    ) -> SharedAuthTokens {
        SharedAuthTokens(
            accessToken: jwt(sub: sub ?? userId.uuidString.lowercased()),
            refreshToken: refresh,
            expiresAt: sdkIssuedAt.addingTimeInterval(expiresAfter),
            issuedAt: issuedAfter.map { sdkIssuedAt.addingTimeInterval($0) }
        )
    }

    private func adopt(_ tokens: SharedAuthTokens) -> Bool {
        SharedSessionReconciler.shouldAdopt(
            shared: tokens,
            sdkRefreshToken: "consumed",
            sdkExpiresAt: sdkExpiresAt,
            sdkIssuedAt: sdkIssuedAt,
            sdkUserId: userId
        )
    }

    func testNewerRotatedPairForSameUserIsAdopted() {
        XCTAssertTrue(adopt(shared()))
    }

    func testUnstampedLegacyPairFallsBackToExpiry() {
        XCTAssertTrue(adopt(shared(issuedAfter: nil)))
        XCTAssertFalse(adopt(shared(issuedAfter: nil, expiresAfter: 1800)))
    }

    func testSameRefreshTokenIsAlreadyInSync() {
        XCTAssertFalse(adopt(shared(refresh: "consumed")))
    }

    func testOlderPairIsNeverAdopted() {
        XCTAssertFalse(adopt(shared(issuedAfter: -60, expiresAfter: 3540)))
        // Later expiry but stamped before the SDK session: a late mirror write.
        XCTAssertFalse(adopt(shared(issuedAfter: -60, expiresAfter: 5400)))
    }

    func testDifferentUserIsNeverAdopted() {
        XCTAssertFalse(adopt(shared(sub: UUID().uuidString)))
    }

    func testUndecodableAccessTokenIsNeverAdopted() {
        let tokens = SharedAuthTokens(
            accessToken: "not-a-jwt",
            refreshToken: "rotated",
            expiresAt: sdkExpiresAt.addingTimeInterval(600)
        )
        XCTAssertFalse(adopt(tokens))
    }

    func testSubjectIsReadFromBase64URLPayload() {
        let sub = userId.uuidString.lowercased()
        XCTAssertEqual(SharedSessionReconciler.jwtSubject(jwt(sub: sub)), sub)
        XCTAssertNil(SharedSessionReconciler.jwtSubject("a.b"))
    }

    func testTokensWithoutStampStillDecode() throws {
        let legacy = #"{"accessToken":"a","refreshToken":"r","expiresAt":"2026-01-01T00:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let tokens = try decoder.decode(SharedAuthTokens.self, from: Data(legacy.utf8))
        XCTAssertEqual(tokens.refreshToken, "r")
        XCTAssertNil(tokens.issuedAt)
    }
}
