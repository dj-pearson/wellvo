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

    // MARK: - Help requests and "not due yet"

    func testTodaysHelpRequestIsShown() {
        let r = receiver("needs_help", "2026-03-10 08:15")
        XCTAssertEqual(r.status(asOf: date("2026-03-10 21:00"), calendar: calendar), "needs_help")
    }

    /// Yesterday's help request is not today's status.
    func testYesterdaysHelpRequestRevertsToPending() {
        let r = receiver("needs_help", "2026-03-09 08:15")
        XCTAssertEqual(r.status(asOf: date("2026-03-10 09:00"), calendar: calendar), "pending")
    }

    func testNotDueYetOnlyHoldsForTheDayItWasComputed() {
        var r = receiver("upcoming", nil)
        r.statusDate = date("2026-03-10 06:00")
        XCTAssertEqual(r.status(asOf: date("2026-03-10 07:00"), calendar: calendar), "upcoming")
        XCTAssertEqual(r.status(asOf: date("2026-03-11 07:00"), calendar: calendar), "pending")
        // Written by an older build (no statusDate): don't trust it.
        XCTAssertEqual(receiver("upcoming", nil).status(asOf: date("2026-03-10 07:00"), calendar: calendar), "pending")
    }

    func testAHelpRequestOutranksAMiss() {
        let state = SharedOwnerState(
            receivers: [
                SharedOwnerReceiver(id: "1", name: "Dad", status: "missed", lastCheckInAt: nil),
                SharedOwnerReceiver(id: "2", name: "Mom", status: "needs_help", lastCheckInAt: date("2026-03-10 08:00")),
            ],
            updatedAt: date("2026-03-10 08:00")
        )
        XCTAssertEqual(state.mostRelevant(asOf: date("2026-03-10 09:00"), calendar: calendar)?.name, "Mom")
    }
}

/// Extensions pass: the owner widget now carries what the dashboard shows —
/// stood down, which kind of help, the receiver's zone, who is on it.
final class SharedOwnerWidgetTruthTests: XCTestCase {

    private var chicago: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        return cal
    }

    private func date(_ value: String, zone: String = "America/Chicago") -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    func testAStoodDownMissReadsAsAlertsStoppedNotMissed() {
        let r = SharedOwnerReceiver(id: "1", name: "Dad", status: "missed", lastCheckInAt: nil,
                                    statusDate: date("2026-03-10 09:40"), stoodDown: true)
        XCTAssertEqual(r.status(asOf: date("2026-03-10 10:00"), calendar: chicago), "stood_down")
        XCTAssertEqual(r.label(forStatus: "stood_down"), "Alerts stopped")
    }

    /// Yesterday's stand-down says nothing about today.
    func testYesterdaysStandDownIsNotCarriedOver() {
        let r = SharedOwnerReceiver(id: "1", name: "Dad", status: "missed", lastCheckInAt: nil,
                                    statusDate: date("2026-03-09 09:40"), stoodDown: true)
        XCTAssertEqual(r.status(asOf: date("2026-03-10 08:00"), calendar: chicago), "pending")
    }

    func testAStoodDownMissNoLongerOutranksAnEscalatingOne() {
        let state = SharedOwnerState(
            receivers: [
                SharedOwnerReceiver(id: "1", name: "Dad", status: "missed", lastCheckInAt: nil,
                                    statusDate: date("2026-03-10 09:40"), stoodDown: true),
                SharedOwnerReceiver(id: "2", name: "Mom", status: "pending", lastCheckInAt: nil,
                                    statusDate: date("2026-03-10 09:40")),
            ],
            updatedAt: date("2026-03-10 09:40")
        )
        XCTAssertEqual(state.mostRelevant(asOf: date("2026-03-10 10:00"), calendar: chicago)?.name, "Mom")
    }

    func testAnSOSOutranksOtherHelpRequests() {
        let state = SharedOwnerState(
            receivers: [
                SharedOwnerReceiver(id: "1", name: "Mom", status: "needs_help", lastCheckInAt: date("2026-03-10 08:00"), helpKind: "call_me"),
                SharedOwnerReceiver(id: "2", name: "Sam", status: "needs_help", lastCheckInAt: date("2026-03-10 08:05"), helpKind: "sos"),
            ],
            updatedAt: date("2026-03-10 08:05")
        )
        XCTAssertEqual(state.mostRelevant(asOf: date("2026-03-10 09:00"), calendar: chicago)?.name, "Sam")
    }

    /// The Lock Screen used to say "2 of 3 checked in" on the morning Mom asked
    /// for help.
    func testTheLockScreenHeadlineNamesWhoNeedsHelp() {
        let now = date("2026-03-10 09:00")
        func state(_ r: SharedOwnerReceiver) -> SharedOwnerState {
            SharedOwnerState(receivers: [r], updatedAt: now)
        }
        XCTAssertEqual(state(SharedOwnerReceiver(id: "1", name: "Mom", status: "needs_help", lastCheckInAt: now, helpKind: "need_help"))
            .headline(asOf: now, calendar: chicago), "Mom needs help")
        XCTAssertEqual(state(SharedOwnerReceiver(id: "1", name: "Mom", status: "needs_help", lastCheckInAt: now, helpKind: "call_me"))
            .headline(asOf: now, calendar: chicago), "Mom asked you to call")
        XCTAssertEqual(state(SharedOwnerReceiver(id: "1", name: "Dad", status: "missed", lastCheckInAt: nil))
            .headline(asOf: now, calendar: chicago), "No answer from Dad")
        XCTAssertNil(state(SharedOwnerReceiver(id: "1", name: "Dad", status: "checked_in", lastCheckInAt: now))
            .headline(asOf: now, calendar: chicago))
    }

    /// Owner in New York, Dad in Los Angeles: Dad's 11 PM Monday check-in is
    /// 2 AM Tuesday in New York. On Tuesday morning it must not read as
    /// Tuesday's check-in.
    func testDayScopingUsesTheReceiversZone() {
        let r = SharedOwnerReceiver(id: "1", name: "Dad", status: "checked_in",
                                    lastCheckInAt: date("2026-03-09 23:00", zone: "America/Los_Angeles"),
                                    timeZoneId: "America/Los_Angeles")
        let tuesdayMorningNY = date("2026-03-10 08:00", zone: "America/New_York")
        XCTAssertEqual(r.status(asOf: tuesdayMorningNY), "pending")
        XCTAssertNil(r.lastCheckIn(asOf: tuesdayMorningNY))
    }

    func testTimesCarryTheZoneWhenItDiffersFromTheViewers() {
        let r = SharedOwnerReceiver(id: "1", name: "Dad", status: "checked_in",
                                    lastCheckInAt: nil, timeZoneId: "America/Los_Angeles")
        let at = date("2026-07-10 08:15", zone: "America/Los_Angeles")
        let inNY = r.timeText(at, viewerZone: TimeZone(identifier: "America/New_York")!)
        let inLA = r.timeText(at, viewerZone: TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertTrue(inNY.hasSuffix(TimeZone(identifier: "America/Los_Angeles")!.abbreviation(for: at)!))
        XCTAssertFalse(inLA.contains(TimeZone(identifier: "America/Los_Angeles")!.abbreviation(for: at)!))
    }

    func testAStoodDownReceiverDoesNotNeedAttention() {
        let now = date("2026-03-10 10:00")
        let state = SharedOwnerState(
            receivers: [SharedOwnerReceiver(id: "1", name: "Dad", status: "missed", lastCheckInAt: nil,
                                            statusDate: now, stoodDown: true)],
            updatedAt: now
        )
        XCTAssertFalse(state.needsAttention(asOf: now, calendar: chicago))
    }

    /// A snapshot written before these fields existed still decodes.
    func testAnOlderSnapshotStillDecodes() throws {
        let json = "{\"receivers\":[{\"id\":\"1\",\"name\":\"Mom\",\"status\":\"missed\"}],\"updatedAt\":\"2026-03-10T14:00:00Z\"}"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(SharedOwnerState.self, from: Data(json.utf8))
        XCTAssertNil(state.receivers[0].stoodDown)
        XCTAssertNil(state.receivers[0].timeZoneId)
    }
}

final class FamilyStatusSpeechTests: XCTestCase {
    func testSiriLeadsWithWhoNeedsHelpAndSaysHowOldTheSnapshotIs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let utc = TimeZone(identifier: "UTC")!
        let state = SharedOwnerState(
            receivers: [
                SharedOwnerReceiver(id: "1", name: "Dad", status: "checked_in", lastCheckInAt: now.addingTimeInterval(-600), timeZoneId: "UTC"),
                SharedOwnerReceiver(id: "2", name: "Mom", status: "needs_help", lastCheckInAt: now.addingTimeInterval(-300), helpKind: "call_me", timeZoneId: "UTC"),
            ],
            updatedAt: now.addingTimeInterval(-2 * 3600)
        )
        let speech = FamilyStatusSpeech.summary(state, now: now, viewerZone: utc)
        XCTAssertTrue(speech.hasPrefix("Mom asked you to call."), speech)
        XCTAssertTrue(speech.contains("Dad checked in at"), speech)
        XCTAssertTrue(speech.contains("2 hours ago"), speech)
    }
}
