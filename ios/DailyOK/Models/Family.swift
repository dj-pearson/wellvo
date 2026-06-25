import Foundation

enum SubscriptionTier: String, Codable {
    /// Legacy tier, kept for grandfathered families created before the
    /// Caregiver tier launched. New signups never land here.
    case free
    /// Lowest paid tier, sized for 1 Receiver + 3 Viewers (the dementia-
    /// caregiver persona). $3.99/mo or $29.99/yr.
    case caregiver
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
    /// Grandfathering deadline for legacy Free-tier families. When set and in
    /// the past, clients should gate paid features and prompt the Owner to
    /// upgrade to Caregiver. NULL for families created after the Caregiver
    /// tier migration.
    var freeTierExpiresAt: Date?
    var maxReceivers: Int
    var maxViewers: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerId = "owner_id"
        case subscriptionTier = "subscription_tier"
        case subscriptionStatus = "subscription_status"
        case subscriptionExpiresAt = "subscription_expires_at"
        case freeTierExpiresAt = "free_tier_expires_at"
        case maxReceivers = "max_receivers"
        case maxViewers = "max_viewers"
        case createdAt = "created_at"
    }

    /// True once a grandfathered Free-tier family's free window has lapsed
    /// (migration 00019 sets a 90-day deadline). Paid features should be gated
    /// and an upgrade prompt shown past this point (US-IOS097). A nil deadline
    /// means no grandfather window applies (so never "expired").
    var isFreeTierExpired: Bool {
        guard subscriptionTier == .free, let deadline = freeTierExpiresAt else { return false }
        return deadline < Date()
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
