import Foundation
import WatchKit
import WidgetKit

@MainActor
final class WatchCheckInModel: ObservableObject {
    @Published var state: SharedCheckInState?
    @Published var isCheckingIn = false
    @Published var didCheckIn = false
    /// True when the check-in is saved locally but not yet confirmed by the
    /// server (no network + phone unreachable). It syncs automatically later.
    @Published var queued = false
    @Published var errorMessage: String?

    init() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        reload()
    }

    var isSignedIn: Bool { state != nil }

    func reload() {
        state = SharedCheckInStore.load()
        queued = WatchOfflineQueue.hasPending
        // Derive doneness from the check-in's day, not the raw persisted flag,
        // so a new day (crossed without a phone sync) re-enables the tap.
        didCheckIn = (state?.isCheckedIn() ?? false) || queued
    }

    private var batteryLevel: Double? {
        let raw = WKInterfaceDevice.current().batteryLevel
        return raw >= 0 ? Double(raw) : nil
    }

    func checkIn() async {
        guard !isCheckingIn else { return }
        // The server dedupes per day, but skip a pointless round-trip if we
        // already know *today's* check-in landed. Use the day-scoped check so a
        // stale flag from a previous day can't block a real new-day check-in.
        if state?.isCheckedIn() == true {
            didCheckIn = true
            return
        }

        isCheckingIn = true
        errorMessage = nil

        do {
            let updated = try await SharedCheckInClient.checkIn(source: "watch", batteryLevel: batteryLevel)
            state = updated
            didCheckIn = true
            queued = false
            WatchOfflineQueue.clear()
            WKInterfaceDevice.current().play(.success)
            WidgetCenter.shared.reloadAllTimelines()
            WatchConnectivityProvider.shared.notifyPhoneOfCheckIn()
        } catch SharedCheckInError.transport {
            // Offline (and phone unreachable, or the phone-side path would have
            // handled it). Queue it and confirm optimistically — it syncs later.
            WatchOfflineQueue.enqueue()
            queued = true
            didCheckIn = true
            WKInterfaceDevice.current().play(.success)
            WidgetCenter.shared.reloadAllTimelines()
            WatchConnectivityProvider.shared.notifyPhoneOfCheckIn()
        } catch SharedCheckInError.sessionExpired {
            // Force the actionable error to show even if a stale snapshot flag
            // would otherwise have left the "all set" state on screen.
            didCheckIn = false
            errorMessage = SharedCheckInError.sessionExpired.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        } catch {
            errorMessage = (error as? SharedCheckInError)?.localizedDescription
                ?? "Couldn't check in. Please try again."
            WKInterfaceDevice.current().play(.failure)
        }

        isCheckingIn = false
    }

    /// Flush a queued check-in when connectivity returns (called on launch,
    /// foreground, and when a fresh snapshot arrives from the phone).
    /// Re-entrancy guard: onAppear, onChange(revision), and onChange(scenePhase)
    /// can all fire in the same runloop on reconnect. Set on the main actor
    /// before the first await so overlapping calls bail instead of each POSTing
    /// the queued check-in and clearing the queue.
    private var isSyncing = false

    func syncPendingIfNeeded() async {
        guard WatchOfflineQueue.hasPending, !isCheckingIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        // Flush with the queued response type so a help/call request isn't
        // downgraded to a plain "OK" on sync (US-IOS119).
        let queuedType = WatchOfflineQueue.pendingType
        do {
            let updated = try await SharedCheckInClient.checkIn(responseType: queuedType, source: "watch", batteryLevel: batteryLevel)
            state = updated
            didCheckIn = true
            queued = false
            WatchOfflineQueue.clear()
            WidgetCenter.shared.reloadAllTimelines()
            WatchConnectivityProvider.shared.notifyPhoneOfCheckIn()
        } catch {
            // Still offline or the session needs the phone — keep it queued.
        }
    }
}
