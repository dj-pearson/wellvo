import Foundation
import WatchConnectivity
import WidgetKit

/// Receives the check-in snapshot the iPhone publishes via
/// `WCSession.updateApplicationContext` and persists it into the watch's local
/// App Group store so `SharedCheckInClient` can perform a check-in standalone.
/// Also notifies the phone when a check-in happens on the wrist.
final class WatchConnectivityProvider: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityProvider()

    /// Bumped whenever a fresh snapshot arrives so SwiftUI can re-read the store.
    @Published var revision = 0

    private override init() { super.init() }

    private var rotationObserver: NSObjectProtocol?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // Pick up any context that arrived before the UI was ready.
        applyContext(session.receivedApplicationContext)

        // The watch refreshed the session itself (its copy had expired). Hand
        // the rotated pair back to the phone: Supabase rotates the refresh
        // token on use, so the phone's copy is now spent, and presenting it
        // would trip reuse detection and sign the receiver out everywhere.
        if rotationObserver == nil {
            rotationObserver = NotificationCenter.default.addObserver(
                forName: SharedCheckInClient.tokensRotated, object: nil, queue: .main
            ) { [weak self] _ in
                self?.sendRotatedTokensToPhone()
            }
        }
    }

    private func sendRotatedTokensToPhone() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let tokens = SharedKeychain.loadTokens() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tokens) else { return }
        WCSession.default.transferUserInfo([WatchHandoff.rotatedTokensKey: data])
    }

    /// Tell the phone a check-in from the watch REACHED THE SERVER, with when
    /// and what. `transferUserInfo` is queued and delivered reliably.
    ///
    /// Only for a delivered check-in: the bare `["watch_checked_in": true]`
    /// this used to send after a merely-queued tap, or after flushing a marker
    /// from an earlier day, made the phone mark TODAY done — and sync that back
    /// here, where it blocked the real check-in.
    func notifyPhoneOfCheckIn(at date: Date, type: String) {
        guard WCSession.isSupported() else { return }
        // transferUserInfo traps if the session isn't activated yet — guard it
        // (US-IOS090).
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(WatchHandoff.checkInReport(at: date, type: type))
    }

    private func applyContext(_ context: [String: Any]) {
        guard let data = context["checkin_state"] as? Data else { return }
        let previous = SharedCheckInStore.load()
        if data.isEmpty {
            // Signed out, left, or removed on the phone. The queued wrist taps
            // go too: they are the previous person's, and would otherwise be
            // sent as whoever signs in next.
            SharedCheckInStore.clear()
            SharedKeychain.clearTokens()
            WatchOfflineQueue.clear()
        } else {
            SharedAppGroup.defaults?.set(data, forKey: SharedAppGroup.Key.checkInState)
            if let current = SharedCheckInStore.load(), previous?.receiverId != current.receiverId {
                WatchOfflineQueue.dropForeign(keeping: current.receiverId)
            }
            // Tokens arrive separately (they're not in the snapshot plist) and
            // are persisted to the watch's own Keychain. An empty/absent blob
            // clears them so a stale session can't be used on the wrist.
            if let tokenData = context["auth_tokens"] as? Data, !tokenData.isEmpty {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let tokens = try? decoder.decode(SharedAuthTokens.self, from: tokenData) {
                    // Never older-over-newer. The context is re-applied on every
                    // launch and holds whatever the phone last sent; if the watch
                    // has refreshed since, writing the context back would restore
                    // a refresh token the watch already spent.
                    SharedKeychain.saveTokensIfNotOlder(tokens)
                } else {
                    SharedKeychain.clearTokens()
                }
            } else {
                SharedKeychain.clearTokens()
            }
        }
        // The complication reads the same snapshot — but only reload it when a
        // glanceable field actually changed. Reloading on every context push can
        // exhaust the watchOS complication update budget, after which it stops
        // updating entirely (US-IOS107).
        let current = SharedCheckInStore.load()
        let glanceChanged = previous?.hasCheckedInToday != current?.hasCheckedInToday
            || previous?.lastCheckInAt != current?.lastCheckInAt
            || previous?.helpKind != current?.helpKind
            || previous?.latestRequestAt != current?.latestRequestAt
            || (previous == nil) != (current == nil)
        if glanceChanged {
            WidgetCenter.shared.reloadAllTimelines()
        }
        DispatchQueue.main.async { self.revision += 1 }
    }

    // MARK: WCSessionDelegate (watchOS requires only this one)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        applyContext(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }
}

/// The watch → phone hand-off payloads. Keys are additive: an older phone build
/// reads only `watch_checked_in` and ignores the rest.
enum WatchHandoff {
    static let rotatedTokensKey = "rotated_tokens"

    static func checkInReport(at date: Date, type: String) -> [String: Any] {
        [
            "watch_checked_in": true,
            "sent": true,
            "answered_at": date.timeIntervalSince1970,
            "type": type,
        ]
    }
}
