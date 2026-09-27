import XCTest
@testable import DailyOK

/// The invite link is the receiver's first contact with the app. The server
/// used to send `/invite?token=`, which the AASA (`/invite/*`) never matched
/// and the handler read only from the query; it now sends
/// `/invite/<token>?code=…`. Both forms, and the website's
/// `dailyok://invite?token=` button, must yield the token — and nothing else
/// may.
final class InviteLinkTests: XCTestCase {
    private let sampleToken = String(repeating: "ab", count: 32)

    private func token(from url: String) -> String? {
        URLComponents(string: url).flatMap(DailyOKApp.inviteToken(from:))
    }

    func testPathFormFromTheInviteText() {
        XCTAssertEqual(token(from: "https://dailyok.net/invite/\(sampleToken)?code=123456"), sampleToken)
    }

    func testOlderQueryForm() {
        XCTAssertEqual(token(from: "https://dailyok.net/invite?token=\(sampleToken)"), sampleToken)
    }

    func testWebsiteOpenInAppButton() {
        XCTAssertEqual(token(from: "dailyok://invite?token=\(sampleToken)"), sampleToken)
    }

    func testRejectsMalformedTokens() {
        XCTAssertNil(token(from: "https://dailyok.net/invite/not-a-token"))
        XCTAssertNil(token(from: "https://dailyok.net/invite/abc"))
        XCTAssertNil(token(from: "https://dailyok.net/invite"))
    }

    func testCheckinTimeFromServerDisplaysAsTime() {
        // The server returns Postgres TIME ("08:30:00"); the screens used to
        // parse only "HH:mm" and showed the raw string.
        XCTAssertNotEqual(formatCheckinTimeForDisplay("08:30:00"), "08:30:00")
        XCTAssertEqual(formatCheckinTimeForDisplay("08:30:00"), formatCheckinTimeForDisplay("08:30"))
    }
}

// MARK: - Join consent (preview before redeem)

/// Joining used to happen before the joiner saw anything. The servers now
/// answer `preview: true` with whose family it is; these pin the decoding and
/// the copy, and that an older server's immediate join is still understood.
final class JoinPreviewTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testCodePreviewDecodes() throws {
        let response = try decode(RedeemCodeResponse.self, """
        {"preview":true,"family_id":"f1","family_name":"The Smiths","role":"receiver",
         "owner_name":"Sarah","invite_name":"Mom","checkin_time":"08:30:00",
         "watchers":["Sarah","Tom"],"already_member":false}
        """)
        let preview = try XCTUnwrap(response.joinPreview)
        XCTAssertEqual(preview.role, .receiver)
        XCTAssertEqual(preview.displayOwnerName, "Sarah")
        XCTAssertEqual(preview.headline, "Join Sarah's family?")
        XCTAssertTrue(preview.sharingSentence.contains("Sarah"))
        XCTAssertTrue(preview.sharingSentence.contains("Tom"))
        XCTAssertFalse(preview.alreadyMember)
    }

    /// A server that predates previews ignores the flag and joins at once.
    func testOlderServerJoinIsNotMistakenForAPreview() throws {
        let response = try decode(RedeemCodeResponse.self, """
        {"success":true,"family_id":"f1","role":"viewer","checkin_time":null,"name":"Tom","owner_name":"Sarah"}
        """)
        XCTAssertNil(response.joinPreview)
        XCTAssertEqual(response.success, true)
        XCTAssertEqual(response.joinedRole, .viewer)
    }

    /// Someone typing their own family's code is its owner, not a receiver.
    func testAlreadyMemberKeepsTheRealRole() throws {
        let response = try decode(RedeemCodeResponse.self, """
        {"success":true,"already_member":true,"family_id":"f1","role":"owner"}
        """)
        XCTAssertEqual(response.joinedRole, .owner)
    }

    func testPlaceholderOwnerNameFallsBackToTheFamily() {
        let preview = JoinPreview(
            familyId: "f1", familyName: "The Smiths", role: .receiver, ownerName: "User",
            inviteName: nil, checkinTime: nil, watchers: ["User"], alreadyMember: false
        )
        XCTAssertNil(preview.displayOwnerName)
        XCTAssertNil(preview.watchersList)
        XCTAssertEqual(preview.headline, "Join The Smiths?")
        XCTAssertNil(JoinPreview.presentableName("  "))
        XCTAssertEqual(JoinPreview.presentableName(" Sarah "), "Sarah")
    }

    func testInviteLinkPreviewAndLegacyJoin() throws {
        let preview = try decode(JoinPreviewResponse.self, """
        {"preview":true,"family_id":"f1","role":"viewer","owner_name":"Sarah","watchers":["Sarah"]}
        """)
        guard case .preview(let described) = preview.step else { return XCTFail("expected a preview") }
        XCTAssertEqual(described.role, .viewer)

        let joined = try decode(JoinPreviewResponse.self, """
        {"success":true,"family_id":"f1","role":"receiver","checkin_time":"09:00","owner_name":"Sarah"}
        """)
        guard case .joined(let details) = joined.step else { return XCTFail("expected a join") }
        XCTAssertEqual(details.role, .receiver)
        XCTAssertEqual(details.checkinTime, "09:00")
    }

    /// A full family used to be dropped silently, leaving the invitee on
    /// "How will you use it?" with no reason.
    func testAutoJoinOutcomes() throws {
        let blocked = try decode(AutoJoinResponse.self, """
        {"matched":false,"reason":"limit_reached","message":"This family's plan has no free places."}
        """)
        guard case .blocked(let message) = blocked.check else { return XCTFail("expected blocked") }
        XCTAssertEqual(message, "This family's plan has no free places.")

        let none = try decode(AutoJoinResponse.self, #"{"matched":false,"reason":"no_matching_invite"}"#)
        guard case .noMatch = none.check else { return XCTFail("expected no match") }

        let preview = try decode(AutoJoinResponse.self, """
        {"matched":true,"preview":true,"family_id":"f1","role":"receiver","owner_name":"Sarah","watchers":["Sarah"],"already_member":false}
        """)
        guard case .matched(let result) = preview.check else { return XCTFail("expected a match") }
        XCTAssertTrue(result.isPreview)
        XCTAssertEqual(result.joinPreview.displayOwnerName, "Sarah")

        // An older server joined already.
        let legacy = try decode(AutoJoinResponse.self, #"{"matched":true,"family_id":"f1","role":"receiver"}"#)
        guard case .matched(let joined) = legacy.check else { return XCTFail("expected a match") }
        XCTAssertFalse(joined.isPreview)

        let noFamily = try decode(AutoJoinResponse.self, #"{"matched":true,"family_id":""}"#)
        guard case .noMatch = noFamily.check else { return XCTFail("empty family id is not a match") }
    }

    func testPairingScreenReadsAttemptsRemaining() {
        XCTAssertEqual(PairingCodeEntryView.attemptsRemaining(in: #"{"error":"Invalid","attemptsRemaining":3}"#), 3)
        XCTAssertNil(PairingCodeEntryView.attemptsRemaining(in: "not json"))
        let now = Date()
        XCTAssertTrue(PairingCodeEntryView.lockoutMessage(until: now.addingTimeInterval(12 * 60), now: now).contains("12 minutes"))
        XCTAssertTrue(PairingCodeEntryView.lockoutMessage(until: now.addingTimeInterval(20), now: now).contains("1 minute"))
    }
}

/// Routing state around joining (AppState / ContentView).
@MainActor
final class JoinRoutingTests: XCTestCase {
    func testDeclinedPhoneMatchIsRememberedPerUser() {
        let state = AppState()
        let me = UUID(), someoneElse = UUID()
        let family = "family-\(UUID().uuidString)"
        XCTAssertFalse(state.hasDeclinedAutoJoin(familyId: family, for: me))
        state.declineAutoJoin(familyId: family, for: me)
        XCTAssertTrue(state.hasDeclinedAutoJoin(familyId: family, for: me))
        XCTAssertFalse(state.hasDeclinedAutoJoin(familyId: family, for: someoneElse))
    }

    /// An unexpected sign-out mid-onboarding used to send the next account on
    /// the phone straight into "Name Your Family".
    func testSignOutClearsEverythingInProgress() {
        let state = AppState()
        state.currentUserRole = .receiver
        state.isOnboarding = true
        state.showPairingCodeEntry = true
        state.setupCodeAfterSignIn = true
        state.autoJoinBlockedMessage = "full"
        state.pendingInviteToken = "abcd"

        state.resetForSignOut()

        XCTAssertNil(state.currentUserRole)
        XCTAssertFalse(state.isOnboarding)
        XCTAssertFalse(state.showPairingCodeEntry)
        XCTAssertFalse(state.setupCodeAfterSignIn)
        XCTAssertNil(state.autoJoinBlockedMessage)
        XCTAssertNil(state.pendingInviteToken)
        XCTAssertEqual(state.roleResolution, .resolving)
    }

    func testRoleIsRecheckedOnForegroundOnlyWhenStaleAndIdle() {
        let now = Date()
        let old = now.addingTimeInterval(-16 * 60)
        XCTAssertTrue(ContentView.shouldRecheckRole(role: .receiver, lastResolvedAt: old, busy: false, now: now))
        XCTAssertFalse(ContentView.shouldRecheckRole(role: .receiver, lastResolvedAt: now.addingTimeInterval(-60), busy: false, now: now))
        XCTAssertFalse(ContentView.shouldRecheckRole(role: .receiver, lastResolvedAt: old, busy: true, now: now))
        XCTAssertFalse(ContentView.shouldRecheckRole(role: nil, lastResolvedAt: old, busy: false, now: now))
        XCTAssertFalse(ContentView.shouldRecheckRole(role: .owner, lastResolvedAt: nil, busy: false, now: now))
    }

    func testOwnerOnboardingDefaults() {
        let viewModel = OnboardingViewModel()
        XCTAssertEqual(Calendar.current.component(.hour, from: viewModel.checkinTime), 8)
        XCTAssertEqual(Calendar.current.component(.minute, from: viewModel.checkinTime), 0)

        viewModel.familyName = "The Smiths"
        viewModel.needsOwnerName = true
        XCTAssertFalse(viewModel.canCreateFamily)
        viewModel.ownerName = "Sarah"
        XCTAssertTrue(viewModel.canCreateFamily)
    }
}
