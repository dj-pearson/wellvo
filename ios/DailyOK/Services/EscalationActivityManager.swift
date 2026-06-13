import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts/updates/ends owner Live Activities for receivers who are in an active
/// escalation window. Driven by the dashboard each time it loads. Gated by a
/// per-owner toggle (default on) and the system's activities-enabled flag.
enum EscalationActivityManager {
    static let toggleKey = "escalationLiveActivitiesEnabled"

    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: toggleKey) as? Bool ?? true
    }

    /// Reconcile live activities with the current dashboard state.
    static func sync(cards: [ReceiverStatusCard], familyId: UUID) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }

        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }

        let escalating = cards.filter { $0.status != .checkedIn && $0.escalationStep >= 1 }
        let escalatingIds = Set(escalating.map { $0.id.uuidString })

        // End activities for receivers no longer escalating (checked in / resolved).
        for activity in Activity<EscalationActivityAttributes>.activities
        where !escalatingIds.contains(activity.attributes.receiverId) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        for card in escalating {
            let existing = Activity<EscalationActivityAttributes>.activities
                .first { $0.attributes.receiverId == card.id.uuidString }

            // Preserve the original due time across updates so the timer is stable.
            let dueSince = existing?.content.state.dueSince ?? Date()
            let state = EscalationActivityAttributes.ContentState(
                status: card.status == .missed ? "missed" : "pending",
                escalationStep: card.escalationStep,
                dueSince: dueSince
            )

            if let existing {
                Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
            } else {
                let attributes = EscalationActivityAttributes(
                    receiverName: card.name,
                    receiverPhone: card.phone,
                    receiverId: card.id.uuidString,
                    familyId: familyId.uuidString
                )
                _ = try? Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil)
                )
            }
        }
        #endif
    }

    static func endAll() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<EscalationActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }
}
