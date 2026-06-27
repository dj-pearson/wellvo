import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Mirrors ActivityKit push tokens for the owner's escalation Live Activity to
/// the backend so the server can end/update a running activity via an APNs
/// `liveactivity` push when the escalation resolves while the owner's app is
/// closed (US-IOS127). Without this, a resolved escalation keeps showing a
/// running "Overdue" timer on the Lock Screen until the app is next opened.
///
/// Thread-safety: the task registry is guarded by an `NSLock` (mirroring
/// `LocationService`, US-IOS118) so it can be driven from the nonisolated
/// `EscalationActivityManager.sync` without actor hops.
final class LiveActivityTokenService: @unchecked Sendable {
    static let shared = LiveActivityTokenService()
    private init() {}

    private let lock = NSLock()
    /// activity.id → its token/state observation tasks.
    private var observers: [String: [Task<Void, Never>]] = [:]
    /// activity.id → most recent hex push token, used to deactivate on end.
    private var lastTokenHex: [String: String] = [:]
    private var pushToStartTask: Task<Void, Never>?

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    #if canImport(ActivityKit)
    /// Begin mirroring a running escalation activity's per-activity push token.
    /// Idempotent per activity id, so it is safe to call on every dashboard sync
    /// for both newly-created and already-running activities.
    @available(iOS 16.2, *)
    func track(_ activity: Activity<EscalationActivityAttributes>) {
        let id = activity.id
        let receiverId = activity.attributes.receiverId
        let familyId = activity.attributes.familyId

        lock.lock()
        if observers[id] != nil {
            lock.unlock()
            return // already tracking
        }
        // An activity discovered after relaunch may already hold a token.
        let initialToken = activity.pushToken.map(Self.hex)

        let tokenTask = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                let hex = Self.hex(tokenData)
                self?.setLastToken(hex, for: id)
                await Self.upload(pushToken: hex, receiverId: receiverId, familyId: familyId)
            }
        }
        let stateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    if let hex = self?.takeLastToken(for: id) {
                        await Self.deactivate(pushToken: hex)
                    }
                    break
                }
            }
            self?.stopTracking(id)
        }

        observers[id] = [tokenTask, stateTask]
        if let initialToken { lastTokenHex[id] = initialToken }
        lock.unlock()

        if let initialToken {
            Task { await Self.upload(pushToken: initialToken, receiverId: receiverId, familyId: familyId) }
        }
    }

    /// Observe the push-to-start token so a future release can server-initiate an
    /// escalation activity without an app change (US-IOS127 — stored now, not yet
    /// consumed). iOS 17.2+; older systems simply skip it. Idempotent.
    func startObservingPushToStartToken() {
        guard #available(iOS 17.2, *) else { return }
        lock.lock()
        if pushToStartTask != nil {
            lock.unlock()
            return
        }
        pushToStartTask = Task {
            for await tokenData in Activity<EscalationActivityAttributes>.pushToStartTokenUpdates {
                await Self.uploadStartToken(pushToken: Self.hex(tokenData))
            }
        }
        lock.unlock()
    }
    #endif

    func stopTracking(_ activityId: String) {
        lock.lock()
        let tasks = observers.removeValue(forKey: activityId)
        lastTokenHex[activityId] = nil
        lock.unlock()
        tasks?.forEach { $0.cancel() }
    }

    private func setLastToken(_ hex: String, for id: String) {
        lock.lock()
        lastTokenHex[id] = hex
        lock.unlock()
    }

    private func takeLastToken(for id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastTokenHex[id]
    }

    // MARK: - Backend calls

    private static func upload(pushToken: String, receiverId: String, familyId: String) async {
        do {
            try await EdgeFunctionsClient.invoke("register-live-activity-token", json: [
                "push_token": .string(pushToken),
                "receiver_id": .string(receiverId),
                "family_id": .string(familyId),
                "token_type": .string("update"),
                "active": .bool(true),
            ])
        } catch {
            Log.general.error("Live activity token register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func uploadStartToken(pushToken: String) async {
        do {
            try await EdgeFunctionsClient.invoke("register-live-activity-token", json: [
                "push_token": .string(pushToken),
                "token_type": .string("start"),
                "active": .bool(true),
            ])
        } catch {
            Log.general.error("Live activity start token register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func deactivate(pushToken: String) async {
        do {
            try await EdgeFunctionsClient.invoke("register-live-activity-token", json: [
                "push_token": .string(pushToken),
                "active": .bool(false),
            ])
        } catch {
            Log.general.error("Live activity token deactivate failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
