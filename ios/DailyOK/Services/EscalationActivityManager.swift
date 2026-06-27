import Foundation
import os
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

    /// How long after the due time a still-running activity is marked stale by
    /// the system, so a resolved-but-not-ended timer doesn't count up forever.
    /// Internal (not private) so the timing math is unit-testable (US-IOS110).
    static let staleWindow: TimeInterval = 6 * 60 * 60

    // MARK: - Pure decision logic (testable without ActivityKit — US-IOS110)

    /// Cards that warrant a Live Activity: still unresolved (not checked in) and
    /// at least one escalation step in. Mirrors the owner "escalating" banner gate.
    static func escalatingCards(from cards: [ReceiverStatusCard]) -> [ReceiverStatusCard] {
        cards.filter { $0.status != .checkedIn && $0.escalationStep >= 1 }
    }

    /// The "overdue since" anchor for a card's activity. Preserve an existing
    /// activity's original due time so the timer is stable across updates; on a
    /// cold start use the request's real escalation start (`card.escalationDueSince`)
    /// — NOT `now` — otherwise a long-overdue receiver looks freshly due after the
    /// app is relaunched. Falls back to `now` only when neither is known.
    static func resolvedDueSince(existing: Date?, cardDueSince: Date?, now: Date) -> Date {
        existing ?? cardDueSince ?? now
    }

    /// When a still-running activity should be marked stale by the system so a
    /// resolved-but-not-ended timer stops counting up forever.
    static func staleDate(after dueSince: Date) -> Date {
        dueSince.addingTimeInterval(staleWindow)
    }

    /// Lock Screen status string for a card. Only `.missed` reads as "missed";
    /// everything still in flight is "pending".
    static func statusString(for status: ReceiverCheckInStatus) -> String {
        status == .missed ? "missed" : "pending"
    }

    /// Reconcile live activities with the current dashboard state.
    static func sync(cards: [ReceiverStatusCard], familyId: UUID) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }

        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }

        // Keep the push-to-start token mirrored to the backend (US-IOS127).
        LiveActivityTokenService.shared.startObservingPushToStartToken()

        let escalating = escalatingCards(from: cards)
        let escalatingIds = Set(escalating.map { $0.id.uuidString })

        // End activities for receivers no longer escalating (checked in / resolved).
        for activity in Activity<EscalationActivityAttributes>.activities
        where !escalatingIds.contains(activity.attributes.receiverId) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        for card in escalating {
            let existing = Activity<EscalationActivityAttributes>.activities
                .first { $0.attributes.receiverId == card.id.uuidString }

            // Preserve the original due time across updates so the timer is
            // stable. On a cold start (no existing activity) anchor to the
            // request's real escalation start time — NOT `Date()` — otherwise a
            // receiver who's been overdue for 40 minutes looks freshly due after
            // the app is killed and relaunched.
            let dueSince = resolvedDueSince(
                existing: existing?.content.state.dueSince,
                cardDueSince: card.escalationDueSince,
                now: Date()
            )
            let state = EscalationActivityAttributes.ContentState(
                status: statusString(for: card.status),
                escalationStep: card.escalationStep,
                dueSince: dueSince
            )

            if let existing {
                // Ensure we mirror this activity's push token even if it was
                // started in a previous app session (US-IOS127).
                LiveActivityTokenService.shared.track(existing)
                // Only push an update when something actually changed — avoids
                // redundant ActivityKit churn on every (frequent) dashboard reload.
                guard existing.content.state != state else { continue }
                Task { await existing.update(ActivityContent(state: state, staleDate: staleDate(after: dueSince))) }
            } else {
                let attributes = EscalationActivityAttributes(
                    receiverName: card.name,
                    receiverPhone: card.phone,
                    receiverId: card.id.uuidString,
                    familyId: familyId.uuidString
                )
                do {
                    // Synchronous throwing API — surface failures (e.g. exceeding
                    // the system Live Activity cap) instead of silently dropping
                    // them so the owner isn't left thinking escalation is visible.
                    // Request a push token (.token) so the backend can end this
                    // activity when the escalation resolves while the app is
                    // closed (US-IOS127).
                    let activity = try Activity.request(
                        attributes: attributes,
                        content: ActivityContent(state: state, staleDate: staleDate(after: dueSince)),
                        pushType: .token
                    )
                    LiveActivityTokenService.shared.track(activity)
                } catch {
                    Log.general.error("Failed to start escalation Live Activity: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        #endif
    }

    /// Immediately end any Live Activity for a specific receiver. Call this the
    /// moment a stand-down succeeds (deep link or in-app) so the owner isn't left
    /// staring at a running overdue timer for a situation they already resolved
    /// (US-IOS081) — don't wait for the next dashboard reload.
    static func end(receiverId: String) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<EscalationActivityAttributes>.activities
        where activity.attributes.receiverId == receiverId {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
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
