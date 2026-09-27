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
    /// Whether the activity offers "Stand down". The owner and active
    /// co-caregivers can stand an escalation down, so current builds set true
    /// for both; false (set for co-caregivers by earlier builds) shows "See
    /// who's on it" instead. Optional so an activity started by an older build
    /// (no key) decodes, and reads as true. Shape unchanged, so activities
    /// already running keep decoding.
    var canStandDown: Bool? = nil
}
#endif
