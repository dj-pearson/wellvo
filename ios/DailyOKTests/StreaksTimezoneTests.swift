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
}
