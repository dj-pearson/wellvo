import Foundation
import WatchConnectivity

/// Receives the check-in snapshot the iPhone publishes via
/// `WCSession.updateApplicationContext` and persists it into the watch's local
/// App Group store so `SharedCheckInClient` can perform a check-in standalone.
/// Also notifies the phone when a check-in happens on the wrist.
final class WatchConnectivityProvider: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityProvider()

    /// Bumped whenever a fresh snapshot arrives so SwiftUI can re-read the store.
    @Published var revision = 0

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // Pick up any context that arrived before the UI was ready.
        applyContext(session.receivedApplicationContext)
    }

    /// Let the phone know a check-in just happened on the watch so its UI and
    /// widgets can refresh. `transferUserInfo` is queued and delivered reliably.
    func notifyPhoneOfCheckIn() {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["watch_checked_in": true])
    }

    private func applyContext(_ context: [String: Any]) {
        guard let data = context["checkin_state"] as? Data else { return }
        if data.isEmpty {
            SharedCheckInStore.clear()
        } else {
            SharedAppGroup.defaults?.set(data, forKey: SharedAppGroup.Key.checkInState)
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
