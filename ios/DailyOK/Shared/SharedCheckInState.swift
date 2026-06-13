import Foundation

/// A small, self-contained snapshot the main app publishes to the shared App
/// Group so out-of-process surfaces (App Intents / Siri, widgets, the Control
/// Center control, and the watch) can perform and display a check-in without
/// the full Supabase SDK or a live app session.
///
/// It intentionally carries the mirrored Supabase session and backend config so
/// an extension can POST to the edge function on its own and refresh the token
/// if needed. The phone remains the source of truth: it rewrites this snapshot
/// on every `loadStatus`, and clears it on sign-out.
struct SharedCheckInState: Codable, Equatable {
    // MARK: Identity
    var receiverId: String
    var familyId: String
    var displayName: String?
    var isKidMode: Bool

    // MARK: Auth (mirrored from the phone's Supabase session)
    var accessToken: String
    var refreshToken: String
    /// Absolute expiry of `accessToken`.
    var expiresAt: Date

    // MARK: Backend config (so extensions don't depend on the host Info.plist)
    var supabaseURL: String
    var anonKey: String
    var edgeFunctionsURL: String

    // MARK: Today's status (for glanceable surfaces)
    var hasCheckedInToday: Bool
    var lastCheckInAt: Date?
    var nextCheckInAt: Date?
    var updatedAt: Date

    /// True when the access token is at/near expiry (refresh 60s early).
    var isAccessTokenExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
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
