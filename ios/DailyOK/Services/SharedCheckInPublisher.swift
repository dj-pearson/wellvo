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
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt),
            supabaseURL: Configuration.supabaseURL,
            anonKey: Configuration.supabaseAnonKey,
            edgeFunctionsURL: Configuration.edgeFunctionsURL,
            hasCheckedInToday: hasCheckedInToday,
            lastCheckInAt: lastCheckInAt,
            nextCheckInAt: nextCheckInAt,
            updatedAt: Date()
        )
        SharedCheckInStore.save(state)
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
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.sync()
    }
}
