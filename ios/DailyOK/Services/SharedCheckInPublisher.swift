import Foundation
import Supabase
import WidgetKit

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
        displayName: String?
    ) async {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            clear()
            return
        }

        let state = SharedCheckInState(
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
        SharedCheckInStore.save(state)
        // Secrets go to the encrypted Keychain, never the App Group plist.
        SharedKeychain.saveTokens(SharedAuthTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        ))
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    /// Re-mirror just the session tokens to the shared Keychain (and the watch)
    /// without rebuilding the whole snapshot — used after a biometric unlock to
    /// restore out-of-process check-in once the user has proven presence.
    static func republishTokensFromSession() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else { return }
        SharedKeychain.saveTokens(SharedAuthTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        ))
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    /// Withhold the session tokens from every out-of-process surface (Keychain
    /// + watch) while the app is biometrically locked, so a widget / Siri / watch
    /// tap can't act as the user until biometric auth succeeds. Non-secret
    /// glanceable state is left in place. Reversed by `republishTokensFromSession()`.
    static func withholdTokens() {
        SharedKeychain.clearTokens()
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    /// Optimistically mark today's check-in done (e.g. right after an in-app tap)
    /// without rebuilding the whole snapshot.
    static func markCheckedIn(at date: Date) {
        SharedCheckInStore.update {
            $0.hasCheckedInToday = true
            $0.lastCheckInAt = date
        }
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }

    static func clear() {
        SharedCheckInStore.clear()
        SharedKeychain.clearTokens()
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }
}
