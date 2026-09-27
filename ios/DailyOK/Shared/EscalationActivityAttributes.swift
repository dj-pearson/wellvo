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
    /// Only the family owner can stand an escalation down. A co-caregiver's
    /// activity shows "Open" instead of a "Stand down" that could only answer
    /// "Only the owner can stop alerts". Optional so an activity started by an
    /// older build (no key) decodes, and reads as the owner's (true).
    var canStandDown: Bool? = nil
}
#endif
