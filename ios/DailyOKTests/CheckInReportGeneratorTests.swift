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
}
