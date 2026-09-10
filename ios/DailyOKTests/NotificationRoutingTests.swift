import XCTest
import UserNotifications
@testable import DailyOK

/// Coverage for push-notification action routing (US-IOS110). The mapping from a
/// `UNNotificationResponse.actionIdentifier` to an in-app behavior is the
/// dispatch point for every lock-screen check-in action — a silent mismatch here
/// means a tapped "I'm OK" does nothing and the owner is falsely escalated.
final class NotificationRoutingTests: XCTestCase {

    func testCheckInActionsMapToResponseTypes() {
        XCTAssertEqual(NotificationRoute.route(for: "CHECKIN_OK_ACTION"), .checkIn(.ok))
        XCTAssertEqual(NotificationRoute.route(for: "CHECKIN_NEED_HELP_ACTION"), .checkIn(.needHelp))
        XCTAssertEqual(NotificationRoute.route(for: "CHECKIN_CALL_ME_ACTION"), .checkIn(.callMe))
    }

    func testSnoozeAndCallReceiverActions() {
        XCTAssertEqual(NotificationRoute.route(for: "CHECKIN_SNOOZE_ACTION"), .snooze)
        XCTAssertEqual(NotificationRoute.route(for: "CALL_RECEIVER_ACTION"), .callReceiver)
    }

    /// The server attaches LOCATION_ALERT to geofence, low-battery and viewer
    /// alerts as of the same change that registered this route. Before it, the
    /// registered "View Details" action mapped to `.none` — it opened the app
    /// (the action is `.foreground`) and then sat on whatever screen the owner
    /// had left behind.
    func testViewDetailsActionRoutesToDetails() {
        XCTAssertEqual(NotificationRoute.route(for: "VIEW_LOCATION_ACTION"), .viewDetails)
    }

    func testDefaultActionOpensApp() {
        XCTAssertEqual(NotificationRoute.route(for: UNNotificationDefaultActionIdentifier), .openApp)
    }

    func testUnknownActionsRouteToNone() {
        // Dismiss and any future/unhandled identifier must be inert, not crash or
        // misfire a check-in.
        XCTAssertEqual(NotificationRoute.route(for: UNNotificationDismissActionIdentifier), .none)
        XCTAssertEqual(NotificationRoute.route(for: "SOME_FUTURE_ACTION"), .none)
        XCTAssertEqual(NotificationRoute.route(for: ""), .none)
    }
}
