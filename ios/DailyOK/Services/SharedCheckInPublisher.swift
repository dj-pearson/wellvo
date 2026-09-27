import Foundation
import Supabase
import WidgetKit
import UserNotifications

/// Bridges the live app session into the shared App Group snapshot consumed by
/// Siri, the Shortcuts app, the widget, the Control Center control, and the
/// watch. The phone is the source of truth: it republishes on every status load
/// and clears the snapshot on sign-out.
enum SharedCheckInPublisher {
    /// Publish a full snapshot from the current session + receiver context.
    @MainActor
    static func publish(
        familyId: UUID,
        isKidMode: Bool,
        hasCheckedInToday: Bool,
        lastCheckInAt: Date?,
        nextCheckInAt: Date?,
        displayName: String?,
        ownerName: String? = nil,
        timeZoneId: String? = nil,
        helpKind: String? = nil,
        helpAt: Date? = nil,
        savedOffline: Bool = false
    ) async {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            clear()
            return
        }

        var state = SharedCheckInState(
            receiverId: session.user.id.uuidString.lowercased(),
            familyId: familyId.uuidString.lowercased(),
            displayName: displayName,
            isKidMode: isKidMode,
            supabaseURL: Configuration.supabaseURL,
            anonKey: Configuration.supabaseAnonKey,
            edgeFunctionsURL: Configuration.edgeFunctionsURL,
            hasCheckedInToday: hasCheckedInToday,
            lastCheckInAt: lastCheckInAt,
            nextCheckInAt: nextCheckInAt,
            updatedAt: Date()
        )
        state.ownerName = ownerName
        state.timeZoneId = timeZoneId
        state.helpKind = helpKind
        state.helpAt = helpKind == nil ? nil : (helpAt ?? lastCheckInAt ?? Date())
        // Server truth replaces the NSE's "asked again" stamp: this load already
        // accounted for every pending request (owesAnotherAnswer).
        state.pendingSendSince = savedOffline ? Date() : nil
        SharedCheckInStore.save(state)
        // Secrets go to the encrypted Keychain, never the App Group plist.
        mirrorTokens(from: session)
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    /// Mirror the SDK session to the shared Keychain — unless biometric lock is
    /// withholding it (SharedTokenGate), or the shared item already holds a
    /// NEWER pair another surface rotated (writing ours over it would hand
    /// every surface a spent refresh token; see SharedAuthTokens.shouldReplace).
    static func mirrorTokens(from session: Session) {
        guard SharedTokenGate.mayMirror else {
            // Gate closed means the shared item should be empty. It can still
            // hold a pair at a fresh (often background) launch if the previous
            // process was killed while unlocked — and once the SDK refreshes
            // here, that pair's refresh token is spent. Left in place, the NSE /
            // widget would present it and trip GoTrue's reuse detection, which
            // revokes the whole session. Withheld is the intended state anyway.
            if SharedKeychain.loadTokens() != nil { SharedKeychain.clearTokens() }
            return
        }
        SharedKeychain.saveTokensIfNotOlder(SharedAuthTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        ))
    }

    /// Re-mirror just the session tokens to the shared Keychain (and the watch)
    /// without rebuilding the whole snapshot — used after a biometric unlock to
    /// restore out-of-process check-in once the user has proven presence.
    static func republishTokensFromSession() async {
        SharedTokenGate.markUnlocked()
        guard let session = try? await SupabaseService.shared.client.auth.session else { return }
        mirrorTokens(from: session)
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    /// Withhold the session tokens from every out-of-process surface (Keychain
    /// + watch) while the app is biometrically locked, so a widget / Siri / watch
    /// tap can't act as the user until biometric auth succeeds. Non-secret
    /// glanceable state is left in place. Reversed by `republishTokensFromSession()`.
    static func withholdTokens() {
        SharedTokenGate.markWithheld()
        SharedKeychain.clearTokens()
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    /// Optimistically mark today's check-in done (e.g. right after an in-app tap)
    /// without rebuilding the whole snapshot.
    /// `savedOffline`: the tap is queued on this phone, not yet on the server.
    /// The widget and watch then say "Saved, not sent yet" rather than
    /// "You're all set" (pendingSendSince outranks the done flag there).
    static func markCheckedIn(at date: Date, helpKind: String? = nil, savedOffline: Bool = false) {
        SharedCheckInStore.update {
            $0.hasCheckedInToday = true
            $0.lastCheckInAt = date
            $0.pendingSendSince = savedOffline ? date : nil
            $0.lastFailureMessage = nil
            $0.lastFailureAt = nil
            if let helpKind {
                $0.helpKind = helpKind
                $0.helpAt = date
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    /// Nothing to check in to any more (removed from the family, or a
    /// different role now): drop the snapshot so the widget, Siri, Control
    /// Center and the watch stop offering "I'm OK" for it. Leaves the tokens:
    /// the account is still signed in and the NSE still confirms delivery.
    static func clearSnapshot() {
        guard SharedCheckInStore.load() != nil else { return }
        SharedCheckInStore.clear()
        ExtensionCheckInQueue.clear()
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    /// Undo of today's check-in: flip the snapshot back to "not done" without
    /// touching the session tokens. Undo used to call `clear()`, which also
    /// wiped the tokens and signed the widget, Siri and the watch out until the
    /// next status load.
    static func markNotCheckedIn() {
        SharedCheckInStore.update {
            $0.hasCheckedInToday = false
            $0.lastCheckInAt = nil
        }
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    static func clear() {
        SharedCheckInStore.clear()
        SharedKeychain.clearTokens()
        // The next person to sign in on this phone must not inherit this
        // one's saved widget taps.
        ExtensionCheckInQueue.clear()
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }
}

/// Whether the app may put the session tokens where the widget, Control
/// Center, Siri and the watch can use them.
///
/// Biometric lock withholds them while the app is backgrounded, so a found or
/// handed-off phone can't check in as the receiver before Face ID. Three paths
/// quietly put them back: the launch-time `syncAccessTokenToExtension`
/// (including background launches from a notification action, WatchConnectivity
/// or a Live Activity token update), the SDK's `.tokenRefreshed` event (which
/// fires on resume BEFORE the Face ID prompt) and a receiver status publish.
/// Every app-side write now asks this first.
///
/// Open when biometric lock is off; otherwise only once the user has unlocked
/// in this process. Per-process on purpose: a fresh launch starts locked.
enum SharedTokenGate {
    private static let lock = NSLock()
    private static var unlockedThisProcess = false

    static var mayMirror: Bool {
        lock.lock(); defer { lock.unlock() }
        return !BiometricService.isEnabledPreference || unlockedThisProcess
    }

    /// Presence proven (Face ID / passcode), or biometric lock can't apply.
    static func markUnlocked() {
        lock.lock(); unlockedThisProcess = true; lock.unlock()
    }

    static func markWithheld() {
        lock.lock(); unlockedThisProcess = false; lock.unlock()
    }
}

/// Everything that must happen after a receiver checks in, whichever surface
/// they used (the app, a notification action, a synced offline tap).
///
/// Before this, only the in-app button cancelled the local fallback reminder,
/// and nothing removed the delivered "please check in" banners — so a receiver
/// who answered from the notification was nagged again later, and an open home
/// screen kept showing the "I'm OK" button for a check-in that had landed.
enum ReceiverCheckInAftermath {
    /// Posted after a check-in from outside the home screen (e.g. a notification
    /// action), so an open ReceiverHomeView reloads.
    static let didCheckIn = Notification.Name("ReceiverCheckInAftermath.didCheckIn")

    @MainActor
    static func record(at date: Date, helpKind: String? = nil, savedOffline: Bool = false) async {
        SharedCheckInPublisher.markCheckedIn(at: date, helpKind: helpKind, savedOffline: savedOffline)
        ExtensionCheckInQueue.clearToday()
        await PushNotificationService.shared.cancelLocalCheckinFallback()
        await removeDeliveredCheckInRequests()
        NotificationCenter.default.post(name: didCheckIn, object: nil)
    }

    /// Clear delivered check-in prompts from Notification Center / the Lock
    /// Screen — they are answered.
    static func removeDeliveredCheckInRequests() async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ids = delivered
            .filter { $0.request.content.categoryIdentifier == "CHECKIN_REQUEST" }
            .map(\.request.identifier)
        if !ids.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}
