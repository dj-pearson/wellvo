import Foundation

enum SubscriptionTier: String, Codable {
    case free
    case family
    case familyPlus = "family_plus"
}

enum SubscriptionStatus: String, Codable {
    case active
    case expired
    case gracePeriod = "grace_period"
    case cancelled
}

struct Family: Codable, Identifiable {
    let id: UUID
    var name: String
    let ownerId: UUID
    var subscriptionTier: SubscriptionTier
    var subscriptionStatus: SubscriptionStatus
    var subscriptionExpiresAt: Date?
    var maxReceivers: Int
    var maxViewers: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerId = "owner_id"
        case subscriptionTier = "subscription_tier"
        case subscriptionStatus = "subscription_status"
        case subscriptionExpiresAt = "subscription_expires_at"
        case maxReceivers = "max_receivers"
        case maxViewers = "max_viewers"
        case createdAt = "created_at"
    }
}

struct FamilyMember: Codable, Identifiable {
    let id: UUID
    let familyId: UUID
    let userId: UUID
    var role: UserRole
    var status: MemberStatus
    let invitedAt: Date?
    let joinedAt: Date?

    // Joined fields
    var user: AppUser?

    enum CodingKeys: String, CodingKey {
        case id, role, status
        case familyId = "family_id"
        case userId = "user_id"
        case invitedAt = "invited_at"
        case joinedAt = "joined_at"
        case user = "users"
    }
}
