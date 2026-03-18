import Foundation

enum UserRole: String, Codable, CaseIterable {
    case owner
    case receiver
    case viewer
}

enum MemberStatus: String, Codable {
    case active
    case invited
    case deactivated
}

struct AppUser: Codable, Identifiable {
    let id: UUID
    let email: String?
    let phone: String?
    var displayName: String
    var role: UserRole
    var avatarUrl: String?
    var timezone: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, phone, role, timezone
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
