import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity for an in-progress escalation (a receiver missed their
/// check-in). Shared so the app can start/update/end it and the widget
/// extension can render the Lock Screen + Dynamic Island presentations.
struct EscalationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "pending" (overdue, escalating) or "missed".
        var status: String
        var escalationStep: Int
        /// When the check-in became due — drives the elapsed timer.
        var dueSince: Date
    }

    var receiverName: String
    var receiverPhone: String?
    var receiverId: String
    var familyId: String
}
#endif
