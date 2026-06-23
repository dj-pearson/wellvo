import Foundation
import WatchConnectivity

/// Phone side of the watch hand-off. Pushes the shared check-in snapshot to the
/// Apple Watch via `updateApplicationContext` (delivered even when the watch
/// isn't currently reachable) and listens for check-ins made on the wrist so the
/// app and widgets can refresh.
final class PhoneWatchSync: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchSync()

    /// Posted when the watch reports a check-in; observers should reload status.
    static let didReceiveWatchCheckIn = Notification.Name("PhoneWatchSync.didReceiveWatchCheckIn")

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Mirror the current shared snapshot to the watch. Sending empty data tells
    /// the watch to clear its copy (e.g. on sign-out).
    ///
    /// The session tokens no longer live in the App Group plist, so they're sent
    /// alongside the snapshot under a separate key. WatchConnectivity is an
    /// encrypted, device-to-device channel; the watch stores the tokens in its
    /// own Keychain (not its plist) on receipt.
    func sync() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let data = SharedAppGroup.defaults?.data(forKey: SharedAppGroup.Key.checkInState) ?? Data()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tokenData = SharedKeychain.loadTokens().flatMap { try? encoder.encode($0) } ?? Data()
        try? session.updateApplicationContext([
            "checkin_state": data,
            "auth_tokens": tokenData,
        ])
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Push the latest snapshot as soon as the session is ready.
        if activationState == .activated { sync() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for a swapped watch.
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if userInfo["watch_checked_in"] != nil {
            NotificationCenter.default.post(name: PhoneWatchSync.didReceiveWatchCheckIn, object: nil)
        }
    }
}
