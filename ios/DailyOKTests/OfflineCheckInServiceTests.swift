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

    // MARK: - Queued rows expire with the server's replay window (US-IOS147)

    /// The sync path sends `occurred_at`, so the server records a replayed
    /// check-in against the moment it was made. Past `maxReplayAge` the server
    /// stops honouring that timestamp and falls back to now() — which would
    /// record a days-old tap as TODAY's check-in, telling the owner the receiver
    /// is fine when they may not be. So the client refuses to replay anything
    /// the server would not honour. The two bounds must stay equal:
    /// `OCCURRED_AT_MAX_AGE_MS` in edge-functions/shared/checkin-time.ts.

    func testReplayWindowMatchesTheServerBound() {
        XCTAssertEqual(OfflineCheckInService.maxReplayAge, 7 * 24 * 60 * 60)
    }

    func testRowQueuedMomentsAgoIsNotStale() {
        let now = Date()
        XCTAssertFalse(
            OfflineCheckInService.isStale(queuedAt: now.addingTimeInterval(-30), now: now)
        )
    }

    /// The case the old day-boundary rule got wrong in the other direction: a
    /// row queued at 23:55 and synced at 00:05 is ten minutes old and perfectly
    /// replayable, because the server is told which day it belongs to.
    func testRowQueuedTenMinutesAgoAcrossMidnightIsNotStale() {
        let now = Date()
        XCTAssertFalse(
            OfflineCheckInService.isStale(queuedAt: now.addingTimeInterval(-600), now: now)
        )
    }

    func testRowQueuedThreeDaysAgoIsStillReplayable() {
        let now = Date()
        XCTAssertFalse(
            OfflineCheckInService.isStale(queuedAt: now.addingTimeInterval(-3 * 24 * 3600), now: now)
        )
    }

    func testRowAtTheReplayBoundIsStillReplayable() {
        let now = Date()
        XCTAssertFalse(
            OfflineCheckInService.isStale(
                queuedAt: now.addingTimeInterval(-OfflineCheckInService.maxReplayAge),
                now: now
            )
        )
    }

    func testRowPastTheReplayBoundIsStale() {
        let now = Date()
        XCTAssertTrue(
            OfflineCheckInService.isStale(
                queuedAt: now.addingTimeInterval(-OfflineCheckInService.maxReplayAge - 1),
                now: now
            )
        )
    }

    func testRowQueuedAMonthAgoIsStale() {
        let now = Date()
        XCTAssertTrue(
            OfflineCheckInService.isStale(queuedAt: now.addingTimeInterval(-30 * 24 * 3600), now: now)
        )
    }
}
