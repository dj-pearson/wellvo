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
        queued = WatchOfflineQueue.hasPendingForToday
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
            // Today is settled by this call; anything queued for an EARLIER day
            // is a separate check-in that still has to be sent.
            WatchOfflineQueue.clearToday()
            queued = WatchOfflineQueue.hasPendingForToday
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
        let markers = WatchOfflineQueue.pending
        guard !markers.isEmpty, !isCheckingIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var sentAny = false
        // Oldest first, each carrying the moment it was actually made
        // (US-IOS147), so a tap from a previous day is filed under that day
        // rather than counting as today's check-in. Flushing with the queued
        // response type keeps a help/call request from being downgraded to a
        // plain "OK" (US-IOS119).
        for marker in markers {
            do {
                let updated = try await SharedCheckInClient.checkIn(
                    responseType: marker.type,
                    source: "watch",
                    batteryLevel: batteryLevel,
                    occurredAt: marker.at
                )
                state = updated
                WatchOfflineQueue.remove(marker)
                sentAny = true
            } catch {
                // Still offline or the session needs the phone — keep this one
                // and everything after it queued, and stop: a later marker is
                // no more likely to get through than this one.
                break
            }
        }

        guard sentAny else { return }
        didCheckIn = state?.isCheckedIn() == true
        queued = WatchOfflineQueue.hasPendingForToday
        WidgetCenter.shared.reloadAllTimelines()
        WatchConnectivityProvider.shared.notifyPhoneOfCheckIn()
    }
}
