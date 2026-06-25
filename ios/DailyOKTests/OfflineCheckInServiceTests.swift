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
}
