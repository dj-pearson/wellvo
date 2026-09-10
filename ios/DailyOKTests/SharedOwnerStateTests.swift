import XCTest
@testable import DailyOK

/// The owner widget renders from a snapshot only the phone app writes. If the
/// owner does not open the app — overnight, or for a day, or with background
/// refresh off — the snapshot does not change, and every status in it is
/// whatever was true when they last did.
///
/// A green "checked in ✓" beside a relative's name on a day nobody has answered
/// is the false reassurance this product exists to prevent. The receiver widget
/// has always been day-scoped (`SharedCheckInState.isCheckedIn(asOf:)`); the
/// owner's was not.
final class SharedOwnerStateTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return cal
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func receiver(_ status: String, _ lastCheckIn: String?) -> SharedOwnerReceiver {
        SharedOwnerReceiver(
            id: "r1", name: "Mom", status: status,
            lastCheckInAt: lastCheckIn.map(date)
        )
    }

    // MARK: - A stale "checked in" reverts to "we don't know yet"

    func testYesterdaysCheckInDoesNotReadAsCheckedInToday() {
        let r = receiver("checked_in", "2026-03-09 08:15")
        XCTAssertEqual(r.status(asOf: date("2026-03-10 09:00"), calendar: calendar), "pending")
    }

    func testTodaysCheckInStillReadsAsCheckedIn() {
        let r = receiver("checked_in", "2026-03-10 08:15")
        XCTAssertEqual(r.status(asOf: date("2026-03-10 21:00"), calendar: calendar), "checked_in")
    }

    func testCheckedInWithNoTimestampIsNotTrusted() {
        let r = receiver("checked_in", nil)
        XCTAssertEqual(r.status(asOf: date("2026-03-10 09:00"), calendar: calendar), "pending")
    }

    /// It reverts to "pending", never to "missed". Whether a window has elapsed
    /// is the server's call; a widget guessing it would invent an escalation
    /// nobody raised.
    func testAStaleCheckInIsNeverPromotedToMissed() {
        let r = receiver("checked_in", "2026-03-01 08:15")
        XCTAssertNotEqual(r.status(asOf: date("2026-03-10 09:00"), calendar: calendar), "missed")
    }

    func testOtherStatusesArePassedThroughUntouched() {
        for status in ["pending", "missed", "no_data"] {
            let r = receiver(status, "2026-03-09 08:15")
            XCTAssertEqual(r.status(asOf: date("2026-03-10 09:00"), calendar: calendar), status)
        }
    }

    // MARK: - The timestamp itself

    /// A bare "8:15 AM" in the widget row reads as today. It must not be shown
    /// for a check-in from another day.
    func testAStaleTimestampIsWithheld() {
        let r = receiver("checked_in", "2026-03-09 08:15")
        XCTAssertNil(r.lastCheckIn(asOf: date("2026-03-10 09:00"), calendar: calendar))
    }

    func testTodaysTimestampIsShown() {
        let r = receiver("checked_in", "2026-03-10 08:15")
        XCTAssertEqual(
            r.lastCheckIn(asOf: date("2026-03-10 09:00"), calendar: calendar),
            date("2026-03-10 08:15")
        )
    }

    // MARK: - The summary line and the ordering

    func testTheSummaryCountDoesNotCarryYesterdayForward() {
        let state = SharedOwnerState(
            receivers: [
                SharedOwnerReceiver(id: "1", name: "Mom", status: "checked_in", lastCheckInAt: date("2026-03-09 08:00")),
                SharedOwnerReceiver(id: "2", name: "Dad", status: "checked_in", lastCheckInAt: date("2026-03-10 07:30")),
            ],
            updatedAt: date("2026-03-09 08:00")
        )
        // "2 of 2 checked in" on a day only Dad has answered.
        XCTAssertEqual(state.checkedInCount(asOf: date("2026-03-10 09:00"), calendar: calendar), 1)
    }

    func testAStaleCheckInDoesNotOutrankSomeoneWhoHasNotAnswered() {
        let state = SharedOwnerState(
            receivers: [
                SharedOwnerReceiver(id: "1", name: "Mom", status: "checked_in", lastCheckInAt: date("2026-03-09 08:00")),
                SharedOwnerReceiver(id: "2", name: "Dad", status: "checked_in", lastCheckInAt: date("2026-03-10 07:30")),
            ],
            updatedAt: date("2026-03-09 08:00")
        )
        // Mom is the one who has not answered today, so she is the one to show.
        XCTAssertEqual(
            state.mostRelevant(asOf: date("2026-03-10 09:00"), calendar: calendar)?.name,
            "Mom"
        )
    }

    func testAGenuineMissedStillWinsTheOrdering() {
        let state = SharedOwnerState(
            receivers: [
                SharedOwnerReceiver(id: "1", name: "Mom", status: "checked_in", lastCheckInAt: date("2026-03-09 08:00")),
                SharedOwnerReceiver(id: "2", name: "Dad", status: "missed", lastCheckInAt: nil),
            ],
            updatedAt: date("2026-03-09 08:00")
        )
        XCTAssertEqual(
            state.mostRelevant(asOf: date("2026-03-10 09:00"), calendar: calendar)?.name,
            "Dad"
        )
    }
}
