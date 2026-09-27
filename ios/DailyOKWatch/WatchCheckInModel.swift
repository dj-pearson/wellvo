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
    /// Today's help request ("need_help" / "call_me"), shown instead of "all set".
    @Published var helpKind: String?
    @Published var isSendingHelp = false
    /// Set when the server said this person is no longer in the family: the
    /// snapshot is gone, and the screen says why instead of "sign in".
    @Published var removedMessage: String?

    init() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        reload()
    }

    var isSignedIn: Bool { state != nil }
    var ownerName: String? { state?.ownerName }

    func reload() {
        state = SharedCheckInStore.load()
        if let state {
            // A queue left by whoever wore this watch before must never be sent
            // as this person's check-ins.
            WatchOfflineQueue.dropForeign(keeping: state.receiverId)
            removedMessage = nil
        }
        // Saved on the wrist, or saved on the iPhone (the phone marks a queued
        // tap done so nothing re-prompts, and flags it pending): either way
        // "saved, not sent yet", never "You're all set".
        queued = WatchOfflineQueue.hasPendingForToday || (state?.hasPendingSend() ?? false)
        helpKind = state?.helpRequested()
        // Derive doneness from the check-in's day, not the raw persisted flag,
        // so a new day (crossed without a phone sync) re-enables the tap — and
        // from the latest request, so "check on them now" brings the button
        // back.
        didCheckIn = (state?.isCheckedIn() ?? false) || queued
    }

    private var batteryLevel: Double? {
        let raw = WKInterfaceDevice.current().batteryLevel
        return raw >= 0 ? Double(raw) : nil
    }

    func checkIn() async {
        guard !isCheckingIn else { return }
        // No "already done today" short-circuit: the family may be asking again
        // (a later window, or "check on them now"), and the snapshot on the
        // wrist can't always know. The server dedups a repeat and answers every
        // pending request, so sending is always safe.
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
            WatchConnectivityProvider.shared.notifyPhoneOfCheckIn(at: Date(), type: "ok")
        } catch let error as SharedCheckInError where error.isQueueable {
            saveForLater()
        } catch SharedCheckInError.locked {
            // The iPhone's biometric lock withheld the session. Not a refusal:
            // the tap is saved and sends once the iPhone is unlocked — the same
            // call the notification action has always made.
            saveForLater()
        } catch SharedCheckInError.notInFamily {
            handleRemoved()
        } catch let error as SharedCheckInError {
            // Force the actionable error to show even if a stale snapshot flag
            // would otherwise have left the "all set" state on screen.
            didCheckIn = false
            errorMessage = error.message(ownerName: ownerName)
            WKInterfaceDevice.current().play(.failure)
        } catch {
            didCheckIn = false
            errorMessage = "Couldn't check in. Please try again."
            WKInterfaceDevice.current().play(.failure)
        }

        isCheckingIn = false
    }

    /// Offline / unreachable / iPhone locked: keep the tap and say so. Nothing
    /// was sent, so the phone is NOT told "checked in" — it used to mark today
    /// done on the phone, the widget and back on the watch for a tap the
    /// server never saw.
    private func saveForLater() {
        WatchOfflineQueue.enqueue(state: state)
        queued = true
        didCheckIn = true
        // A lighter tap than success: saved, not delivered.
        WKInterfaceDevice.current().play(.click)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func handleRemoved() {
        WatchOfflineQueue.clear()
        state = nil
        didCheckIn = false
        queued = false
        removedMessage = SharedCheckInError.notInFamily.message(ownerName: nil)
        WKInterfaceDevice.current().play(.failure)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// "I need help" / "Ask them to call me" from the wrist. Live only, like
    /// every other surface: an urgent signal is never saved for silent later
    /// delivery. If it doesn't send, the receiver is told plainly to call.
    func sendHelp(_ responseType: String) async {
        guard !isSendingHelp, responseType == "need_help" || responseType == "call_me" else { return }
        isSendingHelp = true
        errorMessage = nil
        defer { isSendingHelp = false }
        do {
            let updated = try await SharedCheckInClient.checkIn(
                responseType: responseType, source: "watch", batteryLevel: batteryLevel
            )
            state = updated
            helpKind = responseType
            didCheckIn = true
            WKInterfaceDevice.current().play(.success)
            WidgetCenter.shared.reloadAllTimelines()
            WatchConnectivityProvider.shared.notifyPhoneOfCheckIn(at: Date(), type: responseType)
        } catch SharedCheckInError.notInFamily {
            handleRemoved()
        } catch {
            errorMessage = WatchHelpCopy.notSent(ownerName: ownerName)
            WKInterfaceDevice.current().play(.failure)
        }
    }

    /// Flush a queued check-in when connectivity returns (called on launch,
    /// foreground, and when a fresh snapshot arrives from the phone).
    /// Re-entrancy guard: onAppear, onChange(revision), and onChange(scenePhase)
    /// can all fire in the same runloop on reconnect. Set on the main actor
    /// before the first await so overlapping calls bail instead of each POSTing
    /// the queued check-in and clearing the queue.
    private var isSyncing = false

    func syncPendingIfNeeded() async {
        guard let current = SharedCheckInStore.load() else { return }
        let markers = WatchOfflineQueue.dropForeign(keeping: current.receiverId)
        guard !markers.isEmpty, !isCheckingIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var sentToday: OfflineCheckInMarker?
        var sentAny = false
        let calendar = current.receiverCalendar
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
                    occurredAt: marker.at,
                    slotKey: marker.slotKey
                )
                state = updated
                WatchOfflineQueue.remove(marker)
                sentAny = true
                if calendar.isDate(marker.at, inSameDayAs: Date()) { sentToday = marker }
            } catch SharedCheckInError.notInFamily {
                // Never going to land for this family. Say why rather than
                // showing "Saved — will send" for up to a week.
                handleRemoved()
                return
            } catch let error as SharedCheckInError {
                if case .server(let code, _) = error, (400..<500).contains(code), code != 401 {
                    // A deterministic refusal of THIS marker: drop it so it
                    // can't hold every later one hostage.
                    WatchOfflineQueue.remove(marker)
                    continue
                }
                // Still offline, locked, or the session needs the phone — keep
                // this one and everything after it queued, and stop: a later
                // marker is no more likely to get through than this one.
                break
            } catch {
                break
            }
        }

        guard sentAny else { return }
        reload()
        WidgetCenter.shared.reloadAllTimelines()
        // Only a tap that answered TODAY tells the phone anything about today.
        // A flushed marker from an earlier day used to mark today "done" on
        // the phone, the widget and (synced back) the watch — blocking the
        // real check-in while the server had nothing for today.
        if let sentToday {
            WatchConnectivityProvider.shared.notifyPhoneOfCheckIn(at: sentToday.at, type: sentToday.type)
        }
    }
}

/// Watch copy that has to name the owner.
enum WatchHelpCopy {
    static func notSent(ownerName: String?) -> String {
        "Not sent. Call \(ownerName ?? "your family") now."
    }

    static func sent(_ kind: String, ownerName: String?) -> String {
        let who = ownerName ?? "your family"
        return kind == "call_me" ? "We asked \(who) to call you." : "We told \(who) you need help."
    }
}
