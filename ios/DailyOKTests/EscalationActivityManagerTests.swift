import XCTest
@testable import DailyOK

/// Unit coverage for the owner-escalation Live Activity decision logic
/// (US-IOS110). ActivityKit itself can't run in a unit test, so the timing/state
/// math was extracted into pure helpers — these guard the core safety behavior:
/// who gets an activity, what the overdue anchor is, and when it goes stale.
final class EscalationActivityManagerTests: XCTestCase {

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    /// Build a status card with only the fields escalation cares about.
    private func card(
        status: ReceiverCheckInStatus,
        step: Int,
        dueSince: Date? = nil
    ) -> ReceiverStatusCard {
        ReceiverStatusCard(
            id: UUID(),
            memberId: UUID(),
            name: "Mom",
            avatarUrl: nil,
            phone: nil,
            status: status,
            lastCheckIn: nil,
            streak: 0,
            consistencyPercent: 0,
            mood: nil,
            hasNotificationsEnabled: true,
            checkedInTime: nil,
            locationLabel: nil,
            kidResponseType: nil,
            escalationStep: step,
            escalationDueSince: dueSince
        )
    }

    // MARK: - escalatingCards

    func testEscalatingCardsExcludesCheckedInAndStepZero() {
        let cards = [
            card(status: .checkedIn, step: 3),   // resolved — excluded
            card(status: .pending, step: 0),     // not escalating yet — excluded
            card(status: .pending, step: 1),     // escalating — included
            card(status: .missed, step: 2),      // escalating — included
        ]
        let escalating = EscalationActivityManager.escalatingCards(from: cards)
        XCTAssertEqual(escalating.count, 2)
        XCTAssertTrue(escalating.allSatisfy { $0.status != .checkedIn && $0.escalationStep >= 1 })
    }

    func testEscalatingCardsEmptyWhenNoneQualify() {
        let cards = [card(status: .checkedIn, step: 1), card(status: .noData, step: 0)]
        XCTAssertTrue(EscalationActivityManager.escalatingCards(from: cards).isEmpty)
    }

    // MARK: - resolvedDueSince (overdue anchor survives app restart)

    func testResolvedDueSincePrefersExistingActivityAnchor() {
        let existing = date("2026-06-10T08:00:00Z")
        let cardDue = date("2026-06-10T09:00:00Z")
        let now = date("2026-06-10T10:00:00Z")
        // An already-running activity keeps its original due time so the timer
        // doesn't jump on every dashboard reload.
        XCTAssertEqual(
            EscalationActivityManager.resolvedDueSince(existing: existing, cardDueSince: cardDue, now: now),
            existing
        )
    }

    func testResolvedDueSinceFallsBackToCardDueOnColdStart() {
        let cardDue = date("2026-06-10T09:00:00Z")
        let now = date("2026-06-10T10:00:00Z")
        // No existing activity (cold start): anchor to the request's real
        // escalation start, NOT now — otherwise a 1h-overdue receiver looks
        // freshly due after a relaunch.
        XCTAssertEqual(
            EscalationActivityManager.resolvedDueSince(existing: nil, cardDueSince: cardDue, now: now),
            cardDue
        )
    }

    func testResolvedDueSinceFallsBackToNowWhenNothingKnown() {
        let now = date("2026-06-10T10:00:00Z")
        XCTAssertEqual(
            EscalationActivityManager.resolvedDueSince(existing: nil, cardDueSince: nil, now: now),
            now
        )
    }

    // MARK: - staleDate

    func testStaleDateIsSixHoursAfterDue() {
        let due = date("2026-06-10T08:00:00Z")
        XCTAssertEqual(EscalationActivityManager.staleWindow, 6 * 60 * 60)
        XCTAssertEqual(
            EscalationActivityManager.staleDate(after: due),
            date("2026-06-10T14:00:00Z")
        )
    }

    // MARK: - statusString

    func testStatusStringMapsMissedAndPending() {
        XCTAssertEqual(EscalationActivityManager.statusString(for: .missed), "missed")
        XCTAssertEqual(EscalationActivityManager.statusString(for: .pending), "pending")
        // Only .missed reads as missed; anything else in flight is "pending".
        XCTAssertEqual(EscalationActivityManager.statusString(for: .noData), "pending")
        XCTAssertEqual(EscalationActivityManager.statusString(for: .checkedIn), "pending")
    }
}
