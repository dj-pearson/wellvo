import Foundation

/// A small, self-contained snapshot the main app publishes to the shared App
/// Group so out-of-process surfaces (App Intents / Siri, widgets, the Control
/// Center control, and the watch) can perform and display a check-in without
/// the full Supabase SDK or a live app session.
///
/// It carries only NON-SECRET identity, backend config, and glanceable status.
/// The Supabase session secrets (access/refresh token + expiry) are kept out of
/// this App Group `UserDefaults` plist — which is plaintext and lands in device
/// backups — and live in the encrypted Keychain via `SharedKeychain`. The phone
/// remains the source of truth: it rewrites this snapshot on every `loadStatus`,
/// and clears it (and the Keychain tokens) on sign-out.
struct SharedCheckInState: Codable, Equatable {
    // MARK: Identity
    var receiverId: String
    var familyId: String
    var displayName: String?
    var isKidMode: Bool

    // MARK: Backend config (so extensions don't depend on the host Info.plist)
    var supabaseURL: String
    var anonKey: String
    var edgeFunctionsURL: String

    // MARK: Today's status (for glanceable surfaces)
    var hasCheckedInToday: Bool
    var lastCheckInAt: Date?
    var nextCheckInAt: Date?
    var updatedAt: Date
}

extension SharedCheckInState {
    /// Whether today's check-in is actually done *as of `now`*, derived from the
    /// check-in's calendar day rather than trusting the persisted
    /// `hasCheckedInToday` flag on its own.
    ///
    /// `hasCheckedInToday` is only ever flipped *true* (by `markCheckedIn` /
    /// `SharedCheckInClient.checkIn`) and is never cleared at a local-midnight
    /// rollover for out-of-process surfaces — the phone clears it only when it
    /// next runs `loadStatus`. If the phone app isn't opened across midnight, a
    /// watch-only user would otherwise be shown a stale "all set" and have a
    /// real new-day check-in silently short-circuited (a false-escalation risk).
    ///
    /// Uses the device-local calendar; the phone remains the source of truth and
    /// rewrites the snapshot with its own timezone-correct status whenever it
    /// runs. The flag is still required so the phone can authoritatively mark
    /// "not done" even when `lastCheckInAt` happens to land today.
    func isCheckedIn(asOf now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard hasCheckedInToday, let last = lastCheckInAt else { return false }
        return calendar.isDate(last, inSameDayAs: now)
    }
}

/// Read/write access to the shared check-in snapshot. Safe to call from any
/// target that links the shared files and has the App Group entitlement.
enum SharedCheckInStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load() -> SharedCheckInState? {
        guard let data = SharedAppGroup.defaults?.data(forKey: SharedAppGroup.Key.checkInState) else {
            return nil
        }
        return try? decoder.decode(SharedCheckInState.self, from: data)
    }

    static func save(_ state: SharedCheckInState) {
        guard let data = try? encoder.encode(state) else { return }
        SharedAppGroup.defaults?.set(data, forKey: SharedAppGroup.Key.checkInState)
    }

    /// Mutate the existing snapshot in place. No-op if none exists yet.
    static func update(_ mutate: (inout SharedCheckInState) -> Void) {
        guard var state = load() else { return }
        mutate(&state)
        state.updatedAt = Date()
        save(state)
    }

    static func clear() {
        SharedAppGroup.defaults?.removeObject(forKey: SharedAppGroup.Key.checkInState)
    }
}
