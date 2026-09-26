import Foundation
import Supabase

actor FamilyService {
    static let shared = FamilyService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    func createFamily(name: String) async throws -> Family {
        guard let session = try? await supabase.auth.session else {
            throw FamilyError.notAuthenticated
        }

        // Initial *unpaid* limits. We deliberately do NOT grant a paid tier here:
        // a new family starts with a single-receiver allowance, and the
        // subscription webhook upgrades `subscription_tier` / `max_receivers` /
        // `max_viewers` once a purchase is verified. (The `free` tier is the
        // grandfathered unpaid state; gating elsewhere checks the paid tiers via
        // SubscriptionService.hasAccess and the family's max_receivers.)
        let family: Family = try await supabase
            .from("families")
            .insert([
                "name": name,
                "owner_id": session.user.id.uuidString,
                "subscription_tier": SubscriptionTier.free.rawValue,
                "subscription_status": SubscriptionStatus.active.rawValue,
                "max_receivers": "1",
                "max_viewers": "0",
            ])
            .select()
            .single()
            .execute()
            .value

        // Add owner as family member
        try await supabase
            .from("family_members")
            .insert([
                "family_id": family.id.uuidString,
                "user_id": session.user.id.uuidString,
                "role": UserRole.owner.rawValue,
                "status": MemberStatus.active.rawValue,
            ])
            .execute()

        return family
    }

    func getFamily() async throws -> Family? {
        guard let session = try? await supabase.auth.session else { return nil }

        // Pick the earliest-created family the user owns so both devices (owner
        // + receiver) deterministically resolve to the same family when stray
        // duplicates exist in the DB.
        let families: [Family] = try await supabase
            .from("families")
            .select()
            .eq("owner_id", value: session.user.id.uuidString)
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value

        if let family = families.first { return family }

        // Check if user is a member of a family — earliest join wins for the
        // same reason as above.
        let memberships: [FamilyMember] = try await supabase
            .from("family_members")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .eq("status", value: MemberStatus.active.rawValue)
            .order("joined_at", ascending: true)
            .limit(1)
            .execute()
            .value

        guard let membership = memberships.first else { return nil }

        let family: Family = try await supabase
            .from("families")
            .select()
            .eq("id", value: membership.familyId.uuidString)
            .single()
            .execute()
            .value

        return family
    }

    /// Returns the current user's role in their family, or nil if they have no
    /// membership. Used on every launch to route owners, receivers and viewers.
    ///
    /// THROWS when the lookup fails. It used to swallow errors with `try?` and
    /// return nil, and ContentView treats nil as "no family yet" — so a receiver
    /// who opened the app offline was shown the owner's screens. Only a
    /// successful, empty answer means nil now.
    func getCurrentUserRole() async throws -> UserRole? {
        // A session that can't be loaded (offline with an expired access token)
        // is a failed lookup, not "no family".
        let session = try await supabase.auth.session

        // If the user owns any family, they are an owner. This takes precedence
        // over any receiver/viewer memberships they may also hold (e.g. if the
        // same account was invited into another family for testing).
        let ownedFamilies: [Family] = try await supabase
            .from("families")
            .select("id")
            .eq("owner_id", value: session.user.id.uuidString)
            .limit(1)
            .execute()
            .value

        if !ownedFamilies.isEmpty {
            return .owner
        }

        let members: [FamilyMember] = try await supabase
            .from("family_members")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .eq("status", value: MemberStatus.active.rawValue)
            .limit(1)
            .execute()
            .value

        return members.first?.role
    }

    func getFamilyMembers(familyId: UUID) async throws -> [FamilyMember] {
        let members: [FamilyMember] = try await supabase
            .from("family_members")
            .select("*, users(*)")
            .eq("family_id", value: familyId.uuidString)
            .execute()
            .value

        return members
    }

    /// Create a pending invite for a receiver and return everything the app
    /// needs to deliver it *natively* from the owner's own device.
    ///
    /// The invitation is no longer sent server-side via Twilio: an invite goes
    /// to someone who hasn't opted into our A2P 10DLC campaign, so it can't ride
    /// the approved sender (Twilio won't approve it). Instead the backend just
    /// records the invite (so phone-based auto-join works) and hands back a
    /// pre-composed message the caller drops into the iOS Messages composer, so
    /// the text comes from the owner's personal number. The Twilio campaign is
    /// reserved for escalation alerts only.
    @discardableResult
    func inviteReceiver(familyId: UUID, name: String, phone: String, checkinTime: String) async throws -> InviteDetails {
        let response: InviteResponse = try await EdgeFunctionsClient.invoke(
            "invite-receiver",
            body: [
                "family_id": familyId.uuidString,
                "name": name,
                "phone": phone,
                "checkin_time": checkinTime,
            ]
        )

        // Prefer the server-composed body (keeps the copy in one place), but
        // fall back to a locally-built message so an older backend that doesn't
        // return `invite_message` still produces a sendable invite.
        let message = response.inviteMessage ?? InviteDetails.fallbackMessage(
            name: name,
            pairingCode: response.pairingCode
        )

        return InviteDetails(
            phone: phone,
            message: message,
            pairingCode: response.pairingCode,
            inviteLink: response.inviteLink
        )
    }

    /// Invites this family has sent that nobody has used yet and that haven't
    /// expired — "waiting to join". Read straight from invite_tokens (owners
    /// have RLS read on their own family's invites). A re-send expires the
    /// earlier invite server-side, so each person appears once.
    func pendingInvites(familyId: UUID) async throws -> [PendingInvite] {
        // Filtered here rather than with IS NULL / > filters so this only uses
        // query builders already exercised elsewhere in the app. Expired rows
        // are purged nightly (00005), so the recent window is small.
        let recent: [PendingInvite] = try await supabase
            .from("invite_tokens")
            .select("id, name, phone, checkin_time, pairing_code, created_at, expires_at, used_by")
            .eq("family_id", value: familyId.uuidString)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value
        let now = Date()
        return recent.filter { $0.usedBy == nil && $0.expiresAt > now }
    }

    /// Cancel an invite: its link and setup code stop working at once. Expires
    /// it rather than deleting it, so the record of what was sent remains.
    func cancelInvite(id: UUID) async throws {
        try await supabase
            .from("invite_tokens")
            .update(["expires_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func removeMember(memberId: UUID) async throws {
        try await supabase
            .from("family_members")
            .update(["status": MemberStatus.deactivated.rawValue])
            .eq("id", value: memberId.uuidString)
            .execute()
    }

    /// Accept an invite link. Returns what the server says about the family
    /// joined (both fields are nil against an older backend).
    @discardableResult
    func acceptInvite(token: String) async throws -> JoinDetails {
        let response: JoinDetailsResponse = try await EdgeFunctionsClient.invoke(
            "invite-receiver",
            body: [
                "action": "accept",
                "token": token,
                "timezone": TimeZone.current.identifier,
            ]
        )
        return JoinDetails(checkinTime: response.checkinTime, ownerName: response.ownerName)
    }

    /// Redeem a 6-digit pairing code (iPad / alternate-device setup).
    /// Returns the join result from the server.
    func redeemPairingCode(_ code: String) async throws -> RedeemCodeResponse {
        try await EdgeFunctionsClient.invoke(
            "redeem-code",
            body: ["code": code, "timezone": TimeZone.current.identifier]
        )
    }

    /// Check if the authenticated user's phone matches a pending invite and auto-join.
    /// Returns the auto-join result, or nil if no match found.
    func checkAutoJoin() async throws -> AutoJoinResult? {
        // The device zone lets the server schedule check-ins at the receiver's
        // local time from the first day (optional field; older servers ignore it).
        let data: AutoJoinResponse = try await EdgeFunctionsClient.invoke(
            "auto-join",
            body: ["timezone": TimeZone.current.identifier]
        )

        // A match with no family_id is not actionable — emitting an empty string
        // would just make a downstream UUID(uuidString:) fail. Treat it as "no
        // match" instead.
        guard data.matched, let familyId = data.familyId, !familyId.isEmpty else { return nil }

        return AutoJoinResult(
            familyId: familyId,
            role: data.role ?? "receiver",
            checkinTime: data.checkinTime,
            ownerName: data.ownerName
        )
    }
}

/// Everything the UI needs to hand an invite to the native iOS Messages
/// composer. `Identifiable` so views can drive a `.sheet(item:)` from it.
struct InviteDetails: Identifiable {
    let id = UUID()
    /// Recipient phone number, as the owner typed it (the composer normalizes).
    let phone: String
    /// Pre-composed message body — App Store link + optional pairing code.
    let message: String
    let pairingCode: String?
    let inviteLink: String?

    /// Local fallback body used only when the backend doesn't return a
    /// server-composed `invite_message` (older edge-functions build). Kept in
    /// sync with the server copy in `invite-receiver`. No STOP/HELP footer — this
    /// is a person-to-person message from the owner's own number, not A2P.
    static func fallbackMessage(name: String, pairingCode: String?) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = trimmed.isEmpty ? "Hi!" : "Hi \(trimmed)!"
        var body =
            "\(greeting) I'd like to check in with you every day using Daily OK. " +
            "Download the app and sign in with this phone number and we'll be " +
            "connected automatically: https://apps.apple.com/app/daily-ok/id6742044109"
        if let code = pairingCode, !code.isEmpty {
            body += "\n\nSetting up on an iPad? Use this code: \(code)"
        }
        return body
    }
}

/// An invite that has been sent but not yet used.
struct PendingInvite: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String?
    let phone: String?
    /// Postgres TIME, e.g. "08:30:00".
    let checkinTime: String?
    let pairingCode: String?
    let createdAt: Date
    let expiresAt: Date
    let usedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name, phone
        case checkinTime = "checkin_time"
        case pairingCode = "pairing_code"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case usedBy = "used_by"
    }
}

/// Raw decode of the `invite-receiver` response.
struct InviteResponse: Decodable {
    let success: Bool?
    let inviteToken: String?
    let inviteLink: String?
    let pairingCode: String?
    let inviteMessage: String?

    enum CodingKeys: String, CodingKey {
        case success
        case inviteToken = "invite_token"
        case inviteLink = "invite_link"
        case pairingCode = "pairing_code"
        case inviteMessage = "invite_message"
    }
}

struct RedeemCodeResponse: Decodable {
    let success: Bool?
    let alreadyMember: Bool?
    let familyId: String?
    let role: String?
    let checkinTime: String?
    let name: String?
    let ownerName: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case alreadyMember = "already_member"
        case familyId = "family_id"
        case role
        case checkinTime = "checkin_time"
        case name
        case ownerName = "owner_name"
        case error
    }
}

struct AutoJoinResponse: Decodable {
    let matched: Bool
    let alreadyMember: Bool?
    let familyId: String?
    let role: String?
    let checkinTime: String?
    let ownerName: String?

    enum CodingKeys: String, CodingKey {
        case matched
        case alreadyMember = "already_member"
        case familyId = "family_id"
        case role
        case checkinTime = "checkin_time"
        case ownerName = "owner_name"
    }
}

struct AutoJoinResult {
    let familyId: String
    let role: String
    let checkinTime: String?
    var ownerName: String? = nil
}

/// What a successful join tells the receiver's onboarding screen.
struct JoinDetails {
    let checkinTime: String?
    let ownerName: String?
}

/// Raw decode of a successful invite-receiver accept.
struct JoinDetailsResponse: Decodable {
    let checkinTime: String?
    let ownerName: String?

    enum CodingKeys: String, CodingKey {
        case checkinTime = "checkin_time"
        case ownerName = "owner_name"
    }
}

/// "08:30" or "08:30:00" (the server sends Postgres TIME) → locale-aware short
/// time ("8:30 AM"). Falls back to the input if it can't be parsed.
func formatCheckinTimeForDisplay(_ time: String) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "HH:mm"
    guard let date = parser.date(from: String(time.prefix(5))) else { return time }
    let display = DateFormatter()
    display.timeStyle = .short
    display.dateStyle = .none
    return display.string(from: date)
}

enum FamilyError: LocalizedError {
    case notAuthenticated
    case familyNotFound
    case memberLimitReached

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in"
        case .familyNotFound: return "Family not found"
        case .memberLimitReached: return "You've reached the maximum number of members for your plan"
        }
    }
}
