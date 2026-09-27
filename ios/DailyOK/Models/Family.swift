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

    // Forgiving decode (backward-compat rule): a tier this build doesn't know —
    // a future paid tier returned to an older app — must NOT throw the whole
    // `Family` decode. That previously took down the owner dashboard and the
    // receiver's status/check-in for every installed older build. Unknown →
    // `.free`: real feature gating uses the StoreKit-derived
    // `SubscriptionService.currentTier`, and a future-tier family carries no
    // free-tier grandfather deadline, so nothing is wrongly gated.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SubscriptionTier(rawValue: raw) ?? .free
    }
}

enum SubscriptionStatus: String, Codable {
    case active
    case expired
    case gracePeriod = "grace_period"
    case cancelled

    // Forgiving decode: an unknown status (e.g. a future "paused"/"trial") must
    // not throw the `Family` decode. Unknown → `.active` (nothing gates on this
    // field today; the neutral choice avoids a false expiry banner).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SubscriptionStatus(rawValue: raw) ?? .active
    }
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

extension SubscriptionTier {
    /// The plan's name as the store sells it ("Family Plus", not "Family_plus").
    var displayName: String {
        switch self {
        case .free: return String(localized: "Free")
        case .caregiver: return String(localized: "Caregiver")
        case .family: return String(localized: "Family")
        case .familyPlus: return String(localized: "Family Plus")
        }
    }

    /// Nothing larger to upgrade to.
    var isTopTier: Bool { self == .familyPlus }
}

/// The Family tab's rules, kept free of SwiftUI so they can be tested.
///
/// What the tab guarantees:
/// - Everyone who holds or is about to take a seat is counted: an unused
///   invite takes a slot, so the owner can't invite two people into one seat
///   and have the second told "no free slots" on their own phone.
/// - Ownership only goes to an active co-caregiver (viewer). A receiver made
///   owner stops being checked on (dispatch only asks receivers).
/// - Removed members are listed apart and offer nothing that can't work.
/// - An invite nobody used never just disappears: it shows as expired.
enum FamilyRoster {
    /// Seats of one kind (people checked on, or co-caregivers).
    struct SlotUsage: Equatable {
        /// Members holding the seat (joined, or legacy "invited" member rows).
        let used: Int
        /// Open invites for this kind of seat, one per person.
        let waiting: Int
        let limit: Int

        var taken: Int { used + waiting }
        var isFull: Bool { taken >= limit }
    }

    /// Digits of a phone number, without a NANP leading 1 (the server's rule).
    static func phoneDigits(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") { return String(digits.dropFirst()) }
        return digits
    }

    /// Members still in the family: owner first, then the people checked on,
    /// then co-caregivers, each by name. The server returns no order.
    static func currentMembers(_ members: [FamilyMember]) -> [FamilyMember] {
        members.filter { $0.status != .deactivated }.sorted(by: memberOrder)
    }

    /// Removed members (and anyone paused by a plan change), by name.
    static func removedMembers(_ members: [FamilyMember]) -> [FamilyMember] {
        members.filter { $0.status == .deactivated }.sorted(by: memberOrder)
    }

    private static func memberOrder(_ a: FamilyMember, _ b: FamilyMember) -> Bool {
        func rank(_ role: UserRole) -> Int {
            switch role {
            case .owner: return 0
            case .receiver: return 1
            case .viewer: return 2
            }
        }
        if rank(a.role) != rank(b.role) { return rank(a.role) < rank(b.role) }
        let an = a.user?.displayName ?? ""
        let bn = b.user?.displayName ?? ""
        if an != bn { return an.localizedStandardCompare(bn) == .orderedAscending }
        return a.id.uuidString < b.id.uuidString
    }

    /// The newest invite this member joined with (its `used_by` is them). A
    /// removed member's user row is unreadable under RLS, so this is where the
    /// Family tab gets the name and number to show and to invite again.
    static func joinInvite(for member: FamilyMember, in rows: [PendingInvite]) -> PendingInvite? {
        rows.filter { $0.usedBy == member.userId }.max { $0.createdAt < $1.createdAt }
    }

    /// nil for nil, empty or whitespace-only text.
    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Only an active co-caregiver can become owner.
    static func canTransferOwnership(to member: FamilyMember) -> Bool {
        member.role == .viewer && member.status == .active
    }

    static func canRemove(_ member: FamilyMember) -> Bool {
        member.role != .owner && member.status != .deactivated
    }

    /// The owner opens a current receiver's schedule and alerts.
    static func opensSettings(_ member: FamilyMember, isOwner: Bool) -> Bool {
        isOwner && member.role == .receiver && member.status != .deactivated
    }

    static func usage(
        for role: UserRole,
        members: [FamilyMember],
        openInvites: [PendingInvite],
        limit: Int
    ) -> SlotUsage {
        let holders = members.filter { $0.role == role && $0.status != .deactivated }
        let memberPhones = Set(holders.compactMap { $0.user?.phone }.map(phoneDigits).filter { !$0.isEmpty })
        var people = Set<String>()
        for invite in openInvites where invite.invitedRole == role {
            let digits = phoneDigits(invite.phone ?? "")
            // Someone already seated who also has a stray invite is one person.
            if !digits.isEmpty, memberPhones.contains(digits) { continue }
            people.insert(digits.isEmpty ? invite.id.uuidString : digits)
        }
        return SlotUsage(used: holders.count, waiting: people.count, limit: limit)
    }

    /// Recent invite rows → the invites still waiting, and the ones that
    /// expired unused (kept 30 days server-side, 00058) for someone who hasn't
    /// joined. One row per person: the newest invite to a number decides. A
    /// newer invite (re-send) or a used one hides the older rows; a cancelled
    /// invite is not "expired".
    static func partitionInvites(
        _ rows: [PendingInvite],
        members: [FamilyMember],
        now: Date = Date()
    ) -> (open: [PendingInvite], expired: [PendingInvite]) {
        var newestByPerson: [String: PendingInvite] = [:]
        for row in rows {
            let digits = phoneDigits(row.phone ?? "")
            let key = digits.isEmpty ? row.id.uuidString : digits
            if let current = newestByPerson[key], current.createdAt >= row.createdAt { continue }
            newestByPerson[key] = row
        }
        let joinedPhones = Set(
            members.filter { $0.status == .active }
                .compactMap { $0.user?.phone }
                .map(phoneDigits)
                .filter { !$0.isEmpty }
        )

        var open: [PendingInvite] = []
        var expired: [PendingInvite] = []
        for invite in newestByPerson.values where invite.usedBy == nil {
            if invite.expiresAt > now {
                open.append(invite)
            } else if isNaturalExpiry(invite),
                      now.timeIntervalSince(invite.expiresAt) < 30 * 86_400,
                      !joinedPhones.contains(phoneDigits(invite.phone ?? "")) {
                expired.append(invite)
            }
        }
        let newestFirst: (PendingInvite, PendingInvite) -> Bool = { $0.createdAt > $1.createdAt }
        return (open.sorted(by: newestFirst), expired.sorted(by: newestFirst))
    }

    /// Ran its full life (7 days by default) rather than being cancelled or
    /// replaced early, which the server records as an expiry at that moment.
    static func isNaturalExpiry(_ invite: PendingInvite) -> Bool {
        invite.expiresAt.timeIntervalSince(invite.createdAt) >= 6 * 86_400
    }

    /// "expires today" / "expires tomorrow" / "expires in 3 days", counted in
    /// calendar days (a fresh 7-day invite reads 7, not 6).
    static func expiryText(expiresAt: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: expiresAt)
        ).day ?? 0
        switch days {
        case ..<1: return String(localized: "expires today")
        case 1: return String(localized: "expires tomorrow")
        default: return String(localized: "expires in \(days) days")
        }
    }
}

extension FamilyRoster {
    /// What the plan badge says.
    enum PlanState: Equatable {
        case active
        /// Payment failed; the store is retrying (grace period).
        case renewSoon
        /// Auto-renew is off; the plan runs until this date.
        case endsOn(Date)
        case expired
    }

    static func planState(_ family: Family, now: Date = Date()) -> PlanState {
        if family.subscriptionTier == .free, let deadline = family.freeTierExpiresAt, deadline < now {
            return .expired
        }
        switch family.subscriptionStatus {
        case .active: return .active
        case .gracePeriod: return .renewSoon
        case .expired: return .expired
        case .cancelled:
            if let end = family.subscriptionExpiresAt, end > now { return .endsOn(end) }
            return .expired
        }
    }

    /// Why an invite can't be sent: the plan's seats for this role are taken
    /// (counting invites still waiting to be used), and what the owner can do.
    static func limitMessage(for role: UserRole, usage: SlotUsage, tier: SubscriptionTier) -> String {
        let plan = tier.displayName
        let fix = tier.isTopTier
            ? String(localized: "Remove someone or cancel an invite to free a place.")
            : String(localized: "Upgrade your plan, or remove someone or cancel an invite to free a place.")
        let waiting = usage.waiting > 0
            ? " " + String(localized: "\(usage.waiting) of those places \(usage.waiting == 1 ? "is" : "are") held by an invite waiting to be used.")
            : ""
        if role == .viewer {
            if usage.limit <= 0 {
                return String(localized: "Your \(plan) plan doesn't include co-caregivers. Upgrade to add someone who's told when a check-in is missed.")
            }
            return String(localized: "Your \(plan) plan includes \(usage.limit) co-caregiver\(usage.limit == 1 ? "" : "s").")
                + waiting + " " + fix
        }
        return String(localized: "Your \(plan) plan covers \(usage.limit) \(usage.limit == 1 ? "person" : "people") to check on.")
            + waiting + " " + fix
    }

    /// Text for sending an existing invite another way (share sheet), in the
    /// server's wording (shared/invite-message.ts).
    static func shareMessage(name: String?, role: UserRole, link: String?, code: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = trimmed.isEmpty ? "Hi!" : "Hi \(trimmed)!"
        var lines: [String] = [
            role == .viewer
                ? "\(greeting) I'm using Daily OK to check in on our family each day. Join me so you're told too if a check-in is missed — you won't be asked to check in yourself."
                : "\(greeting) I'd like to check in with you each day using Daily OK — you just tap \"I'm OK\" once a day."
        ]
        if let link, !link.isEmpty {
            lines.append("")
            lines.append("1. Get the app: \(link)")
            lines.append("2. Sign in with this phone number and we're connected.")
        }
        if let code, !code.isEmpty {
            lines.append("")
            lines.append("Using a different phone, an iPad, or no phone number? Enter this setup code in the app: \(code)")
        }
        return lines.joined(separator: "\n")
    }
}
