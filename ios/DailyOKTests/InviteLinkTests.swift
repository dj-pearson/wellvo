import XCTest
@testable import DailyOK

/// The invite link is the receiver's first contact with the app. The server
/// used to send `/invite?token=`, which the AASA (`/invite/*`) never matched
/// and the handler read only from the query; it now sends
/// `/invite/<token>?code=…`. Both forms, and the website's
/// `dailyok://invite?token=` button, must yield the token — and nothing else
/// may.
final class InviteLinkTests: XCTestCase {
    private let token = String(repeating: "ab", count: 32)

    private func token(from url: String) -> String? {
        URLComponents(string: url).flatMap(DailyOKApp.inviteToken(from:))
    }

    func testPathFormFromTheInviteText() {
        XCTAssertEqual(token(from: "https://dailyok.net/invite/\(token)?code=123456"), token)
    }

    func testOlderQueryForm() {
        XCTAssertEqual(token(from: "https://dailyok.net/invite?token=\(token)"), token)
    }

    func testWebsiteOpenInAppButton() {
        XCTAssertEqual(token(from: "dailyok://invite?token=\(token)"), token)
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
