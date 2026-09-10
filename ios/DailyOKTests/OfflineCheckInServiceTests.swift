import XCTest
@testable import DailyOK

/// Tests for offline check-in classification logic.
///
/// `OfflineCheckInService.isConnectivityError` decides whether a failed
/// check-in should be optimistically queued for later sync (genuine offline) or
/// surfaced as an error (server/auth/client failure). Getting this wrong either
/// drops a real offline check-in (false escalation) or queues one that actually
/// succeeded. See US-IOS019.
final class OfflineCheckInServiceTests: XCTestCase {

    private func urlError(_ code: Int) -> NSError {
        NSError(domain: NSURLErrorDomain, code: code)
    }

    // MARK: - Connectivity errors should queue

    func testNotConnectedToInternetIsConnectivityError() {
        XCTAssertTrue(OfflineCheckInService.isConnectivityError(urlError(NSURLErrorNotConnectedToInternet)))
    }

    func testNetworkConnectionLostIsConnectivityError() {
        XCTAssertTrue(OfflineCheckInService.isConnectivityError(urlError(NSURLErrorNetworkConnectionLost)))
    }

    func testTimedOutIsConnectivityError() {
        XCTAssertTrue(OfflineCheckInService.isConnectivityError(urlError(NSURLErrorTimedOut)))
    }

    func testCannotConnectToHostIsConnectivityError() {
        XCTAssertTrue(OfflineCheckInService.isConnectivityError(urlError(NSURLErrorCannotConnectToHost)))
    }

    func testDataNotAllowedIsConnectivityError() {
        XCTAssertTrue(OfflineCheckInService.isConnectivityError(urlError(NSURLErrorDataNotAllowed)))
    }

    func testNetworkErrorOfflineIsConnectivityError() {
        XCTAssertTrue(OfflineCheckInService.isConnectivityError(NetworkError.offline))
    }

    // MARK: - Non-connectivity errors should NOT queue (surface the error)

    func testBadServerResponseIsNotConnectivityError() {
        XCTAssertFalse(OfflineCheckInService.isConnectivityError(urlError(NSURLErrorBadServerResponse)))
    }

    func testUserAuthRequiredIsNotConnectivityError() {
        XCTAssertFalse(OfflineCheckInService.isConnectivityError(urlError(NSURLErrorUserAuthenticationRequired)))
    }

    func testNotAuthenticatedIsNotConnectivityError() {
        XCTAssertFalse(OfflineCheckInService.isConnectivityError(CheckInError.notAuthenticated))
    }

    func testGenericErrorIsNotConnectivityError() {
        let error = NSError(domain: "SomeOtherDomain", code: 42)
        XCTAssertFalse(OfflineCheckInService.isConnectivityError(error))
    }

    // MARK: - Wrapped errors (US-IOS116)

    func testDailyOKNetworkWrappedConnectivityErrorIsConnectivityError() {
        // respondToCheckIn re-wraps as DailyOKError.network(_) before it reaches
        // the classifier; the connectivity signal must survive the unwrap.
        let wrapped = DailyOKError.network(urlError(NSURLErrorNotConnectedToInternet))
        XCTAssertTrue(OfflineCheckInService.isConnectivityError(wrapped))
    }

    func testDailyOKUnknownWrappedConnectivityErrorIsConnectivityError() {
        let wrapped = DailyOKError.unknown(urlError(NSURLErrorNetworkConnectionLost))
        XCTAssertTrue(OfflineCheckInService.isConnectivityError(wrapped))
    }

    func testDailyOKNetworkWrappedServerErrorIsNotConnectivityError() {
        // A wrapped non-connectivity failure (e.g. HTTP 400 bridged via URLError)
        // must NOT be queued as offline.
        let wrapped = DailyOKError.network(urlError(NSURLErrorBadServerResponse))
        XCTAssertFalse(OfflineCheckInService.isConnectivityError(wrapped))
    }

    func testDailyOKServerErrorCaseIsNotConnectivityError() {
        XCTAssertFalse(OfflineCheckInService.isConnectivityError(DailyOKError.serverError("boom")))
    }

    // MARK: - Offline queue dedup is per slot, not per day (US-IOS137)

    /// A receiver on a multi-window custom schedule (US-IOS048) who is offline
    /// all day must get one queued row per window. Before US-IOS137 the dedup
    /// key was the calendar day alone, so the morning row swallowed the evening
    /// tap: nothing was queued, the UI still said "saved", and the owner
    /// escalated on a window the receiver had answered.

    func testSecondWindowOfTheSameDayIsNotADuplicate() {
        XCTAssertFalse(
            OfflineCheckInService.isAlreadyQueued(slotKey: "18:00", amongQueuedSlots: ["09:00"])
        )
    }

    func testRepeatTapOnTheSameWindowIsADuplicate() {
        XCTAssertTrue(
            OfflineCheckInService.isAlreadyQueued(slotKey: "09:00", amongQueuedSlots: ["09:00"])
        )
    }

    func testThirdWindowIsNotADuplicateOfTheFirstTwo() {
        XCTAssertFalse(
            OfflineCheckInService.isAlreadyQueued(slotKey: "21:00", amongQueuedSlots: ["09:00", "18:00"])
        )
    }

    /// nil is the day-level slot: what a single-window schedule produces, and
    /// what every row queued before US-IOS137 carries. Two of them still dedup,
    /// which is the pre-existing behaviour this change must not regress.
    func testTwoDayLevelCheckInsStillDedup() {
        XCTAssertTrue(
            OfflineCheckInService.isAlreadyQueued(slotKey: nil, amongQueuedSlots: [nil])
        )
    }

    /// A day-level row (e.g. queued from an offline notification response, which
    /// has no slot available on-device) must not swallow a windowed tap.
    func testDayLevelRowDoesNotSwallowAWindowedCheckIn() {
        XCTAssertFalse(
            OfflineCheckInService.isAlreadyQueued(slotKey: "18:00", amongQueuedSlots: [nil])
        )
    }

    func testWindowedRowDoesNotSwallowADayLevelCheckIn() {
        XCTAssertFalse(
            OfflineCheckInService.isAlreadyQueued(slotKey: nil, amongQueuedSlots: ["18:00"])
        )
    }

    func testNothingQueuedIsNeverADuplicate() {
        XCTAssertFalse(
            OfflineCheckInService.isAlreadyQueued(slotKey: nil, amongQueuedSlots: [])
        )
        XCTAssertFalse(
            OfflineCheckInService.isAlreadyQueued(slotKey: "09:00", amongQueuedSlots: [])
        )
    }

    // MARK: - Queued rows expire with the day they answer (US-IOS147)

    /// The sync path replays a queued row through `process-checkin-response`,
    /// which stamps `checked_in_at` server-side. A row queued yesterday and
    /// synced today is therefore recorded as TODAY's check-in — the dashboard
    /// then shows "checked in" for a receiver who has not touched their phone.
    /// False reassurance is the one outcome worse than a false escalation, so a
    /// row whose day has passed must be dropped, not replayed.

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return cal
    }

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: iso)!
    }

    func testRowQueuedEarlierTheSameDayIsNotStale() {
        XCTAssertFalse(
            OfflineCheckInService.isStale(
                queuedAt: date("2026-03-10 08:15"),
                now: date("2026-03-10 21:59"),
                calendar: calendar
            )
        )
    }

    func testRowQueuedYesterdayIsStale() {
        XCTAssertTrue(
            OfflineCheckInService.isStale(
                queuedAt: date("2026-03-09 23:50"),
                now: date("2026-03-10 00:05"),
                calendar: calendar
            )
        )
    }

    /// Ten minutes apart, but across midnight: the local day is what the server
    /// dedups on, so this row can no longer answer the window it was queued for.
    func testRowQueuedAcrossMidnightIsStaleEvenIfRecent() {
        XCTAssertTrue(
            OfflineCheckInService.isStale(
                queuedAt: date("2026-03-09 23:55"),
                now: date("2026-03-10 00:05"),
                calendar: calendar
            )
        )
    }

    func testRowQueuedDaysAgoIsStale() {
        XCTAssertTrue(
            OfflineCheckInService.isStale(
                queuedAt: date("2026-03-06 09:00"),
                now: date("2026-03-10 09:00"),
                calendar: calendar
            )
        )
    }

    /// A DST spring-forward day is still one calendar day: a morning row must
    /// remain syncable that evening.
    func testRowQueuedOnADSTTransitionDayIsNotStale() {
        XCTAssertFalse(
            OfflineCheckInService.isStale(
                queuedAt: date("2026-03-08 01:30"),
                now: date("2026-03-08 22:00"),
                calendar: calendar
            )
        )
    }
}
