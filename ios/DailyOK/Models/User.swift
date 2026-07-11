import Foundation

enum UserRole: String, Codable, CaseIterable {
    case owner
    case receiver
    case viewer

    // Forgiving decode (backward-compat rule): an unknown role from a newer
    // backend must not throw the whole family-member list decode. Fail closed to
    // the least-privileged role (`.viewer`, read-only) rather than guessing
    // owner/receiver. (No new case, so `allCases` and the picker are unchanged.)
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UserRole(rawValue: raw) ?? .viewer
    }
}

enum MemberStatus: String, Codable {
    case active
    case invited
    case deactivated

    // Forgiving decode: an unknown status must not throw the member decode.
    // Treat unrecognized as not-active (`.deactivated`).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MemberStatus(rawValue: raw) ?? .deactivated
    }
}

struct AppUser: Codable, Identifiable {
    let id: UUID
    let email: String?
    let phone: String?
    var displayName: String
    var role: UserRole
    var avatarUrl: String?
    // Optional so a joined `users` row with a null timezone (e.g. an account
    // created before timezone capture) doesn't throw the whole member-list
    // decode. Consumers already read this via `user?.timezone` into
    // `String?`-accepting APIs, and it aligns with the receiver path's
    // `TimezoneOnly.timezone: String?`. Unknown/absent falls back to a sensible
    // zone at each use site.
    var timezone: String?
    let createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date?
    var lastBatteryLevel: Double?
    var lastAppVersion: String?

    enum CodingKeys: String, CodingKey {
        case id, email, phone, role, timezone
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSeenAt = "last_seen_at"
        case lastBatteryLevel = "last_battery_level"
        case lastAppVersion = "last_app_version"
    }
}
