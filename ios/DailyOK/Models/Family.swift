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
    /// Who pays for this family's plan (00059). Optional: nil on older servers,
    /// free families, and until the next purchase sync. After an ownership
    /// transfer it stays the ex-owner while their subscription covers it.
    var billingUserId: UUID? = nil

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
        case billingUserId = "billing_user_id"
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

// MARK: - Settings: what the plan means (pure, tested)

/// What the Settings tab says about the family's plan.
///
/// The Settings row used to show the StoreKit tier of whichever Apple ID is on
/// this phone ("Family_plus"), not the family's plan. A new owner after a
/// transfer, an owner on a second phone, or a plan bought on Android all read
/// "Free" with a "View Plans" upsell, while the Family tab said otherwise. The
/// family's plan (from the server) is what decides whether check-ins run, so
/// that is what is shown; the Apple ID's own subscription is explained next to
/// it only when the two disagree.
enum PlanSummary {
    struct Line: Equatable {
        let title: String
        let detail: String?
        let needsAttention: Bool
    }

    static func line(for family: Family, now: Date = Date()) -> Line {
        let plan = family.subscriptionTier.displayName
        let day: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }

        if family.subscriptionTier == .free {
            if let deadline = family.freeTierExpiresAt {
                return deadline < now
                    ? Line(title: plan, detail: String(localized: "Your free period has ended. Choose a plan to keep check-ins running."), needsAttention: true)
                    : Line(title: plan, detail: String(localized: "Free until \(day(deadline)). Choose a plan before then to keep check-ins running."), needsAttention: false)
            }
            return Line(title: plan, detail: nil, needsAttention: false)
        }

        switch FamilyRoster.planState(family, now: now) {
        case .active:
            let detail = family.subscriptionExpiresAt.map { String(localized: "Paid through \(day($0))") }
            return Line(title: plan, detail: detail, needsAttention: false)
        case .renewSoon:
            // grace_period: the store couldn't renew; check-ins keep running for
            // the grace week after the paid period ends.
            let stop = family.subscriptionExpiresAt.map { $0.addingTimeInterval(7 * 24 * 3600) }
            let detail = stop.map { String(localized: "Payment issue. Check-ins stop on \(day($0)) unless the plan renews.") }
                ?? String(localized: "Payment issue. Update your payment method to keep check-ins running.")
            return Line(title: plan, detail: detail, needsAttention: true)
        case .endsOn(let end):
            return Line(title: plan, detail: String(localized: "Ends \(day(end))"), needsAttention: true)
        case .expired:
            return Line(title: plan, detail: String(localized: "Plan ended. Daily check-ins are paused until it's renewed."), needsAttention: true)
        }
    }

    /// What a co-caregiver sees about the plan: which plan, who pays for it,
    /// and — when it needs attention — what that means and who can fix it.
    /// The payer's wording ("Choose a plan", "Update your payment method")
    /// told co-caregivers to do things they can't, and nothing named the plan
    /// or the payer while all was well.
    ///
    /// `payerName` is the paying member's name when known; `payerIsMe` when
    /// this co-caregiver's own Apple ID pays (e.g. the owner before a
    /// hand-over); `ownerName` is who manages the family.
    static func viewerLine(
        for family: Family,
        payerName: String?,
        payerIsMe: Bool,
        ownerName: String?,
        now: Date = Date()
    ) -> Line {
        let plan = family.subscriptionTier.displayName
        let day: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
        let owner = ownerName ?? String(localized: "The family owner")
        // Whoever can fix it: the payer, else the owner.
        let fixer = payerIsMe ? nil : (payerName ?? ownerName)
        let fixerMid = fixer ?? String(localized: "the family owner")

        if family.subscriptionTier == .free {
            guard let deadline = family.freeTierExpiresAt else {
                return Line(title: plan, detail: nil, needsAttention: false)
            }
            return deadline < now
                ? Line(title: plan, detail: String(localized: "The family's free period has ended. \(owner) can choose a plan to keep check-ins running."), needsAttention: true)
                : Line(title: plan, detail: String(localized: "Free until \(day(deadline)). \(owner) can choose a plan before then."), needsAttention: false)
        }

        let paidBy: String? = payerIsMe ? String(localized: "you") : payerName
        switch FamilyRoster.planState(family, now: now) {
        case .active:
            let through = family.subscriptionExpiresAt.map { day($0) }
            let detail: String?
            switch (paidBy, through) {
            case let (who?, date?): detail = String(localized: "Paid by \(who) through \(date)")
            case let (who?, nil): detail = String(localized: "Paid by \(who)")
            case let (nil, date?): detail = String(localized: "Paid through \(date)")
            case (nil, nil): detail = nil
            }
            return Line(title: plan, detail: detail, needsAttention: false)
        case .renewSoon:
            let stop = family.subscriptionExpiresAt.map { day($0.addingTimeInterval(7 * 24 * 3600)) }
            let when = stop.map { String(localized: "Check-ins stop on \($0) unless it renews.") }
                ?? String(localized: "Check-ins stop soon unless it renews.")
            if payerIsMe {
                return Line(title: plan, detail: String(localized: "Your payment didn't go through. \(when) Update it in Manage Subscription."), needsAttention: true)
            }
            let whose = fixer.map { String(localized: "\($0)'s payment") } ?? String(localized: "The plan's payment")
            return Line(title: plan, detail: String(localized: "\(whose) didn't go through. \(when) Let them know."), needsAttention: true)
        case .endsOn(let end):
            if payerIsMe {
                return Line(title: plan, detail: String(localized: "Ends \(day(end)) — renewal is off on your Apple ID. Check-ins pause after that."), needsAttention: true)
            }
            return Line(title: plan, detail: String(localized: "Ends \(day(end)). Check-ins pause after that unless \(fixerMid) renews it."), needsAttention: true)
        case .expired:
            return Line(title: plan, detail: String(localized: "The plan has ended, so daily check-ins are paused. \(owner) can choose a plan to restart them."), needsAttention: true)
        }
    }

    /// How the subscription on this phone's Apple ID relates to the family.
    enum StoreRelation: Equatable {
        /// Nothing to explain.
        case consistent
        /// The family is paid for by another member (e.g. the previous owner).
        case paidByAnotherMember
        /// The family is paid, but not by a subscription on this Apple ID
        /// (another Apple ID, another phone, Android).
        case paidElsewhere
        /// This Apple ID has a plan the family doesn't show yet → Restore.
        case notAppliedYet(SubscriptionTier)
        /// This Apple ID pays, but not for this family (e.g. after handing the
        /// family to someone else). Point to Manage Subscription.
        case payingForNothing(SubscriptionTier)
    }

    static func storeRelation(
        storeTier: SubscriptionTier,
        family: Family?,
        currentUserId: UUID?,
        isOwner: Bool,
        now: Date = Date()
    ) -> StoreRelation {
        guard let family else {
            return storeTier == .free ? .consistent : .payingForNothing(storeTier)
        }
        let familyPaid = family.subscriptionTier != .free && FamilyRoster.planState(family, now: now) != .expired
        let payerIsMe = family.billingUserId == nil || family.billingUserId == currentUserId

        if storeTier == .free {
            guard familyPaid else { return .consistent }
            if !payerIsMe { return isOwner ? .paidByAnotherMember : .consistent }
            return isOwner ? .paidElsewhere : .consistent
        }

        // This Apple ID has a subscription.
        if !isOwner && !(family.billingUserId == currentUserId) {
            return .payingForNothing(storeTier)
        }
        if !familyPaid || rank(family.subscriptionTier) < rank(storeTier) {
            return .notAppliedYet(storeTier)
        }
        return .consistent
    }

    static func relationMessage(_ relation: StoreRelation) -> String? {
        switch relation {
        case .consistent:
            return nil
        case .paidByAnotherMember:
            return String(localized: "Another family member pays for this plan. You don't need to buy one. If you'd like to take it over, you can choose a plan below.")
        case .paidElsewhere:
            return String(localized: "This plan was bought with a different Apple ID or on another device. Manage it from there.")
        case .notAppliedYet(let tier):
            return String(localized: "Your Apple ID has a \(tier.displayName) subscription that isn't applied to this family yet. Tap Restore Purchases.")
        case .payingForNothing(let tier):
            return String(localized: "Your Apple ID is still subscribed to \(tier.displayName), but it doesn't pay for a family you own. If you don't need it, cancel it in Manage Subscription.")
        }
    }

    private static func rank(_ tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: return 0
        case .caregiver: return 1
        case .family: return 2
        case .familyPlus: return 3
        }
    }

    /// Places a plan includes, as the server grants them
    /// (subscription-policy.ts TIER_MAP). Free (legacy) → nil.
    static func seats(for tier: SubscriptionTier) -> (people: Int, coCaregivers: Int)? {
        switch tier {
        case .free: return nil
        case .caregiver: return (1, 3)
        case .family: return (3, 5)
        case .familyPlus: return (6, 10)
        }
    }

    static func seatsLine(people: Int, coCaregivers: Int) -> String {
        let p = people == 1
            ? String(localized: "Check on 1 person")
            : String(localized: "Check on up to \(people) people")
        let c = coCaregivers == 1
            ? String(localized: "1 co-caregiver")
            : String(localized: "\(coCaregivers) co-caregivers")
        return "\(p) · \(c)"
    }

    /// Retention: a shorter window deletes older history for everyone.
    static func retentionShortens(from loaded: Int?, to new: Int) -> Bool {
        guard let loaded else { return false }
        return new < loaded
    }

    /// The day before which check-ins are deleted by a retention window.
    static func retentionCutoff(days: Int, now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }

    /// File name for a data export, e.g. "DailyOK-export-2026-09-27.json".
    static func exportFileName(now: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "DailyOK-export-%04d-%02d-%02d.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Account copy by role (pure, tested)

enum AccountCopy {
    /// Sign-out confirmation. Signing out deactivates this phone's push token,
    /// so for anyone who gets missed-check-in alerts that is the thing to say.
    static func signOutMessage(role: UserRole?) -> String {
        switch role {
        case .owner, .viewer:
            return String(localized: "While you're signed out, this iPhone won't alert you if someone misses a check-in. Sign back in to get alerts again.")
        case .receiver:
            return String(localized: "You'll stop receiving check-in notifications until you sign back in.")
        case .none:
            return String(localized: "Are you sure you want to sign out?")
        }
    }

    /// What deleting the account does, in the user's role.
    static func deleteMessage(role: UserRole?, hasStoreSubscription: Bool) -> String {
        var text: String
        switch role {
        case .owner:
            text = String(localized: "This permanently deletes your account and your family: everyone's check-in history, schedules, care notes and alerts. The people you check on will stop getting check-ins, and co-caregivers will stop getting alerts.")
        case .viewer:
            text = String(localized: "This permanently deletes your account and removes you from the family. You'll stop getting missed-check-in alerts. The family and its history stay with the owner.")
        case .receiver:
            text = String(localized: "This permanently deletes your account and your check-in history, and removes you from the family. You'll stop getting check-ins, and your family won't be alerted about you anymore.")
        case .none:
            text = String(localized: "This permanently deletes your account and all of your data.")
        }
        if hasStoreSubscription {
            text += " " + String(localized: "Your App Store subscription is not cancelled by this. Cancel it in Manage Subscription, or Apple will keep charging you.")
        }
        return text
    }

    /// Plain words for a failed Delete Account / Export (never the raw server
    /// or PostgREST text).
    static func failureMessage(for error: Error, action: String) -> String {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed]
            .contains(urlError.code) {
            return String(localized: "You're offline, so we couldn't \(action). Check your connection and try again.")
        }
        return String(localized: "We couldn't \(action). Please try again. If it keeps happening, contact support at dailyok.net/support.")
    }
}
