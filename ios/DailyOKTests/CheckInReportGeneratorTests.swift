import XCTest
@testable import DailyOK

/// The exported PDF goes to a doctor or a family meeting, so the times printed
/// in it have to be the receiver's, in the reader's clock convention. Two things
/// in it disagreed with each other.
final class CheckInReportGeneratorTests: XCTestCase {

    private func chicago() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        return cal
    }

    private func checkIn(at iso: String) -> CheckIn {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return CheckIn(
            id: UUID(),
            receiverId: UUID(),
            familyId: UUID(),
            checkedInAt: formatter.date(from: iso)!,
            source: .app
        )
    }

    /// ICU separates the time from AM/PM with a narrow no-break space.
    private func spaces(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }

    // MARK: - Average check-in time

    func testAverageIsComputedInTheReceiversTimezone() {
        // 13:00Z and 15:00Z are 08:00 and 10:00 in Chicago (CDT): average 09:00.
        let checkIns = [checkIn(at: "2026-06-10T13:00:00Z"), checkIn(at: "2026-06-10T15:00:00Z")]
        let result = CheckInReportGenerator.averageCheckInTime(
            checkIns, calendar: chicago(), locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(spaces(result), "9:00 AM")
    }

    /// The old implementation built this string by hand with a hardcoded AM/PM,
    /// directly under a comment noting the report's dates are locale-aware. A
    /// reader on a 24-hour clock got a table reading "21:14" and a summary line
    /// three inches above reading "9:14 PM".
    func testAverageFollowsTheReadersClockConvention() {
        let checkIns = [checkIn(at: "2026-06-11T02:14:00Z")] // 21:14 Chicago, Jun 10
        let twentyFourHour = CheckInReportGenerator.averageCheckInTime(
            checkIns, calendar: chicago(), locale: Locale(identifier: "en_GB")
        )
        XCTAssertEqual(spaces(twentyFourHour), "21:14")

        let twelveHour = CheckInReportGenerator.averageCheckInTime(
            checkIns, calendar: chicago(), locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(spaces(twelveHour), "9:14 PM")
    }

    func testMidnightAveragesToTwelveAM() {
        // 05:00 UTC is 00:00 Chicago (CDT). The hand-rolled version special-cased
        // hour 0 to 12; this checks the replacement keeps that right.
        let checkIns = [checkIn(at: "2026-06-10T05:00:00Z")]
        let result = CheckInReportGenerator.averageCheckInTime(
            checkIns, calendar: chicago(), locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(spaces(result), "12:00 AM")
    }

    func testNoonAveragesToTwelvePM() {
        let checkIns = [checkIn(at: "2026-06-10T17:00:00Z")] // 12:00 Chicago
        let result = CheckInReportGenerator.averageCheckInTime(
            checkIns, calendar: chicago(), locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(spaces(result), "12:00 PM")
    }

    func testAnEmptyReportHasNoAverage() {
        XCTAssertEqual(
            CheckInReportGenerator.averageCheckInTime([], calendar: chicago()),
            "—"
        )
    }

    /// The receiver's zone, not the device's — the case the whole timezone
    /// argument exists for: an owner abroad printing a report for a parent
    /// at home.
    func testTheSameCheckInAveragesDifferentlyPerZone() {
        let checkIns = [checkIn(at: "2026-06-11T02:14:00Z")]
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!

        let inChicago = CheckInReportGenerator.averageCheckInTime(
            checkIns, calendar: chicago(), locale: Locale(identifier: "en_GB")
        )
        let inLondon = CheckInReportGenerator.averageCheckInTime(
            checkIns, calendar: london, locale: Locale(identifier: "en_GB")
        )
        XCTAssertEqual(spaces(inChicago), "21:14")   // evening, the day before
        XCTAssertEqual(spaces(inLondon), "03:14")    // small hours, the next day
        XCTAssertNotEqual(inChicago, inLondon)
    }

    // MARK: - Period, counts and streak

    private func utc() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func report(checkIns: [CheckIn], days: [HistoryDay] = [], periodDays: Int = 30, generatedAt: Date) -> CheckInReportGenerator.ReportData {
        CheckInReportGenerator.ReportData(
            receiverName: "Mom", familyName: "Family", checkIns: checkIns,
            periodDays: periodDays, generatedAt: generatedAt, timezone: "UTC", days: days
        )
    }

    /// The fetch reached into the day before the window, so a perfect month
    /// printed "Days Checked In: 31 / 30".
    func testDayCountNeverExceedsThePeriod() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-09-27T15:00:00Z")!
        let checkIns = (0...30).map { offset -> CheckIn in
            let at = utc().date(byAdding: .day, value: -offset, to: formatter.date(from: "2026-09-27T09:00:00Z")!)!
            return CheckIn(id: UUID(), receiverId: UUID(), familyId: UUID(), checkedInAt: at, source: .app)
        }
        let lines = CheckInReportGenerator.summaryLines(for: report(checkIns: checkIns, generatedAt: now), calendar: utc())
        XCTAssertTrue(lines.contains("Days Checked In: 30 / 30"), "\(lines)")
        XCTAssertTrue(lines.contains("Total Check-Ins: 30"), "\(lines)")
    }

    /// Exported at 7 AM before today's check-in, the report said "Current
    /// Streak: 0" while the dashboard said 2.
    func testStreakDoesNotResetBeforeTodaysCheckIn() {
        let now = checkIn(at: "2026-09-27T07:00:00Z").checkedInAt
        let checkIns = [checkIn(at: "2026-09-25T09:00:00Z"), checkIn(at: "2026-09-26T09:00:00Z")]
        let lines = CheckInReportGenerator.summaryLines(for: report(checkIns: checkIns, generatedAt: now), calendar: utc())
        XCTAssertTrue(lines.contains("Current Streak: 2 day(s)"), "\(lines)")
    }

    /// The report lists missed requests and help requests, and counts them.
    func testReportShowsMissedDaysAndHelpRequests() {
        let now = checkIn(at: "2026-09-27T15:00:00Z").checkedInAt
        var help = checkIn(at: "2026-09-26T09:04:00Z")
        help = CheckIn(id: help.id, receiverId: help.receiverId, familyId: help.familyId,
                       checkedInAt: help.checkedInAt, source: .notification, responseType: .needHelp)
        let missed = CheckInRequest(
            id: UUID(), familyId: UUID(), receiverId: UUID(), requestedBy: UUID(),
            type: .scheduled, status: .missed, createdAt: checkIn(at: "2026-09-25T09:00:00Z").checkedInAt,
            respondedAt: nil, escalationStep: 3, nextEscalationAt: nil
        )
        let days = HistoryTimeline.build(
            checkIns: [help], requests: [missed], settings: nil, enrolledSince: nil,
            days: 7, now: now, calendar: utc()
        )
        let data = report(checkIns: [help], days: days, periodDays: 7, generatedAt: now)

        let rows = CheckInReportGenerator.reportRows(days: days, calendar: utc(), locale: Locale(identifier: "en_US"))
        XCTAssertEqual(rows.map(\.event), ["Asked for help", "Check-in not answered · family alerted"])

        let lines = CheckInReportGenerator.summaryLines(for: data, calendar: utc())
        XCTAssertTrue(lines.contains("Checked in on 1 of 2 days a check-in was due (50%)"), "\(lines)")
        XCTAssertTrue(lines.contains("Missed days: 1"), "\(lines)")
        XCTAssertTrue(lines.contains("Help requests (need help / call me / SOS): 1"), "\(lines)")
    }

    func testMoodBreakdownOrderIsStable() {
        func ci(_ mood: Mood) -> CheckIn {
            CheckIn(id: UUID(), receiverId: UUID(), familyId: UUID(), checkedInAt: Date(), mood: mood, source: .app)
        }
        let result = CheckInReportGenerator.moodBreakdownString([ci(.tired), ci(.happy), ci(.happy), ci(.neutral)])
        XCTAssertEqual(result, "Good: 2, Okay: 1, Tired: 1")
    }

    func testReportFileNameIsReadableAndSafe() {
        let start = checkIn(at: "2026-08-29T12:00:00Z").checkedInAt
        let end = checkIn(at: "2026-09-27T12:00:00Z").checkedInAt
        let name = CheckInReportGenerator.fileName(
            receiverName: "Mom/Dad", start: start, end: end, calendar: utc(), locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(name, "Daily OK – Mom Dad – Aug 29–Sep 27.pdf")
    }
}
