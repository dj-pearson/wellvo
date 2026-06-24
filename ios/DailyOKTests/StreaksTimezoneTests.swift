import XCTest
@testable import DailyOK

/// Tests for timezone- and DST-correctness of streak/consistency bucketing and
/// check-in time parsing. See US-IOS022.
final class StreaksTimezoneTests: XCTestCase {

    private func calendar(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    // MARK: - Day bucketing depends on the provided timezone

    /// A check-in at 05:30 UTC on Jun 9 is "today" in UTC but "yesterday"
    /// (Jun 8, 22:30 PDT) in Los Angeles. The consistency window must bucket it
    /// in the provided zone so the receiver's badge agrees with their
    /// "checked in today" status rather than the viewer's device zone.
    func testConsistencyBucketsInProvidedTimezone() {
        let iso = ["2026-06-09T05:30:00Z"]
        let today = date("2026-06-09T18:00:00Z")

        let utc = Streaks.consistencyPercent(
            isoTimestamps: iso, windowDays: 1, calendar: calendar("UTC"), today: today
        )
        let la = Streaks.consistencyPercent(
            isoTimestamps: iso, windowDays: 1, calendar: calendar("America/Los_Angeles"), today: today
        )

        XCTAssertEqual(utc, 100, "Check-in is today in UTC")
        XCTAssertEqual(la, 0, "Same instant is yesterday in Los Angeles")
    }

    func testStreakBucketsInProvidedTimezone() {
        let iso = ["2026-06-09T05:30:00Z"]
        let today = date("2026-06-09T18:00:00Z")

        // UTC: the check-in is today → streak of 1.
        XCTAssertEqual(
            Streaks.currentStreak(isoTimestamps: iso, calendar: calendar("UTC"), today: today),
            1
        )
        // LA: the check-in is yesterday → still a valid streak of 1 (streak walks
        // back from yesterday when today has no check-in yet).
        XCTAssertEqual(
            Streaks.currentStreak(isoTimestamps: iso, calendar: calendar("America/Los_Angeles"), today: today),
            1
        )
    }

    func testCalendarForTimezoneFallsBackToCurrentWhenUnknown() {
        XCTAssertEqual(Calendar.forTimezone(nil).timeZone, Calendar.current.timeZone)
        XCTAssertEqual(Calendar.forTimezone("Not/AZone").timeZone, Calendar.current.timeZone)
        XCTAssertEqual(Calendar.forTimezone("Asia/Tokyo").timeZone, TimeZone(identifier: "Asia/Tokyo"))
    }

    // MARK: - Check-in time parsing

    func testParseCheckinTimeValid() {
        XCTAssertEqual(ReceiverViewModel.parseCheckinTime("09:00")?.hour, 9)
        XCTAssertEqual(ReceiverViewModel.parseCheckinTime("09:00")?.minute, 0)
        XCTAssertEqual(ReceiverViewModel.parseCheckinTime("21:30")?.hour, 21)
        XCTAssertEqual(ReceiverViewModel.parseCheckinTime("21:30")?.minute, 30)
        // Tolerates a trailing seconds component (Postgres `time` values).
        XCTAssertEqual(ReceiverViewModel.parseCheckinTime("08:15:00")?.hour, 8)
        XCTAssertEqual(ReceiverViewModel.parseCheckinTime("08:15:00")?.minute, 15)
    }

    func testParseCheckinTimeInvalid() {
        XCTAssertNil(ReceiverViewModel.parseCheckinTime("nonsense"))
        XCTAssertNil(ReceiverViewModel.parseCheckinTime("25:00"))
        XCTAssertNil(ReceiverViewModel.parseCheckinTime("09:61"))
        XCTAssertNil(ReceiverViewModel.parseCheckinTime("0900"))
        XCTAssertNil(ReceiverViewModel.parseCheckinTime(""))
    }

    // MARK: - US-IOS048: streak/consistency with multiple windows per day

    func testExpectedPerDayConsistencyHalfWhenOneOfTwoHit() {
        // One check-in on a 2-window day over a 1-day window → 50%.
        let iso = ["2026-06-09T08:00:00Z"]
        let today = date("2026-06-09T22:00:00Z")
        let pct = Streaks.consistencyPercent(
            isoTimestamps: iso, expectedPerDay: 2, windowDays: 1, calendar: calendar("UTC"), today: today)
        XCTAssertEqual(pct, 50)
    }

    func testExpectedPerDayConsistencyFullWhenBothHit() {
        let iso = ["2026-06-09T08:00:00Z", "2026-06-09T20:00:00Z"]
        let today = date("2026-06-09T22:00:00Z")
        let pct = Streaks.consistencyPercent(
            isoTimestamps: iso, expectedPerDay: 2, windowDays: 1, calendar: calendar("UTC"), today: today)
        XCTAssertEqual(pct, 100)
    }

    func testExpectedPerDayConsistencyCapsPerDay() {
        // Three check-ins on a 2-window day count at most 2 — no over-credit.
        let iso = ["2026-06-09T08:00:00Z", "2026-06-09T12:00:00Z", "2026-06-09T20:00:00Z"]
        let today = date("2026-06-09T22:00:00Z")
        let pct = Streaks.consistencyPercent(
            isoTimestamps: iso, expectedPerDay: 2, windowDays: 1, calendar: calendar("UTC"), today: today)
        XCTAssertEqual(pct, 100)
    }

    func testExpectedPerDayStreakRequiresAllWindows() {
        // Yesterday hit both windows, today only one → streak counts yesterday
        // (complete) but not today (incomplete).
        let iso = [
            "2026-06-08T08:00:00Z", "2026-06-08T20:00:00Z", // complete
            "2026-06-09T08:00:00Z",                          // incomplete
        ]
        let today = date("2026-06-09T22:00:00Z")
        let streak = Streaks.currentStreak(
            isoTimestamps: iso, expectedPerDay: 2, calendar: calendar("UTC"), today: today)
        XCTAssertEqual(streak, 1)
    }

    func testExpectedPerDayOneMatchesLegacy() {
        // expectedPerDay <= 1 must behave exactly like the single-window API.
        let iso = ["2026-06-09T08:00:00Z"]
        let today = date("2026-06-09T22:00:00Z")
        let cal = calendar("UTC")
        XCTAssertEqual(
            Streaks.currentStreak(isoTimestamps: iso, expectedPerDay: 1, calendar: cal, today: today),
            Streaks.currentStreak(isoTimestamps: iso, calendar: cal, today: today))
        XCTAssertEqual(
            Streaks.consistencyPercent(isoTimestamps: iso, expectedPerDay: 1, windowDays: 7, calendar: cal, today: today),
            Streaks.consistencyPercent(isoTimestamps: iso, windowDays: 7, calendar: cal, today: today))
    }
}
