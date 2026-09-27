import Foundation
import Supabase

actor FamilyService {
    static let shared = FamilyService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    func createFamily(name: String) async throws -> Family {
        guard let session = try? await supabase.auth.session else {
            throw FamilyError.notAuthenticated
        }

        // Idempotent: one owner, one family. Owner onboarding could run this
        // twice (Back from Plans to "Name Your Family Group", or a retry after
        // the membership insert below failed), and each run inserted another
        // family. getFamily() resolves to the EARLIEST one while onboarding
        // invited into the newest, so the owner's first receiver joined a
        // family their dashboard never showed. Reuse the family they own.
        let owned: [Family] = try await supabase
            .from("families")
            .select()
            .eq("owner_id", value: session.user.id.uuidString)
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value
        if let existing = owned.first {
            try await ensureOwnerMembership(familyId: existing.id, userId: session.user.id)
            if existing.name != name {
                return (try? await renameFamily(id: existing.id, to: name)) ?? existing
            }
            return existing
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

    /// The owner's own membership row, inserted if a previous attempt created
    /// the family but not this row. An existing row (unique on family + user)
    /// is fine.
    private func ensureOwnerMembership(familyId: UUID, userId: UUID) async throws {
        struct IdRow: Decodable { let id: UUID }
        let rows: [IdRow] = try await supabase
            .from("family_members")
            .select("id")
            .eq("family_id", value: familyId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        guard rows.isEmpty else { return }
        try await supabase
            .from("family_members")
            .insert([
                "family_id": familyId.uuidString,
                "user_id": userId.uuidString,
                "role": UserRole.owner.rawValue,
                "status": MemberStatus.active.rawValue,
            ])
            .execute()
    }

    /// Rename a family the caller owns (owner onboarding's "Name Your Family
    /// Group" when they come back to it).
    func renameFamily(id: UUID, to name: String) async throws -> Family {
        try await supabase
            .from("families")
            .update(["name": name])
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    /// Set the signed-in user's own display name (what receivers and
    /// co-caregivers see: "Sarah will see when you check in").
    func updateMyDisplayName(_ name: String) async throws {
        guard let session = try? await supabase.auth.session else {
            throw FamilyError.notAuthenticated
        }
        try await supabase
            .from("users")
            .update(["display_name": name])
            .eq("id", value: session.user.id.uuidString)
            .execute()
    }

    /// The signed-in user's display name. `loaded` is false when it couldn't
    /// be read (offline), which is not the same as having no name.
    func myDisplayName() async -> (loaded: Bool, name: String?) {
        guard let session = try? await supabase.auth.session else { return (false, nil) }
        struct NameRow: Decodable {
            let displayName: String?
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
        do {
            let rows: [NameRow] = try await supabase
                .from("users")
                .select("display_name")
                .eq("id", value: session.user.id.uuidString)
                .limit(1)
                .execute()
                .value
            return (true, rows.first?.displayName)
        } catch {
            return (false, nil)
        }
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

    /// Create a pending invite and return everything the app needs to deliver
    /// it *natively* from the owner's own device.
    ///
    /// The invitation is no longer sent server-side via Twilio: an invite goes
    /// to someone who hasn't opted into our A2P 10DLC campaign, so it can't ride
    /// the approved sender (Twilio won't approve it). Instead the backend just
    /// records the invite (so phone-based auto-join works) and hands back a
    /// pre-composed message the caller drops into the iOS Messages composer, so
    /// the text comes from the owner's personal number. The Twilio campaign is
    /// reserved for escalation alerts only.
    ///
    /// `role` is `.receiver` (someone to check on) or `.viewer` (a
    /// co-caregiver). The field is only sent for viewers, so a receiver invite
    /// is the same request older builds make.
    @discardableResult
    func inviteReceiver(
        familyId: UUID,
        name: String,
        phone: String,
        checkinTime: String,
        role: UserRole = .receiver
    ) async throws -> InviteDetails {
        var body: [String: String] = [
            "family_id": familyId.uuidString,
            "name": name,
            "phone": phone,
            "checkin_time": checkinTime,
        ]
        if role == .viewer {
            body["role"] = UserRole.viewer.rawValue
            body.removeValue(forKey: "checkin_time")
        }
        let response: InviteResponse = try await EdgeFunctionsClient.invoke("invite-receiver", body: body)

        // A server from before co-caregiver invites ignores `role` and stores a
        // RECEIVER invite: that person would start getting daily check-ins.
        // Such a server doesn't echo `role`, so withdraw the invite and say so.
        if role == .viewer && response.role != UserRole.viewer.rawValue {
            if let token = response.inviteToken {
                try? await supabase
                    .from("invite_tokens")
                    .update(["expires_at": Self.cancelledExpiry])
                    .eq("token", value: token)
                    .execute()
            }
            throw FamilyError.caregiverInvitesUnavailable
        }

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
            inviteLink: response.inviteLink,
            name: name,
            role: role,
            token: response.inviteToken
        )
    }

    /// This family's recent invites, used or not, newest first. Owners have
    /// RLS read on their own family's invites. `FamilyRoster.partitionInvites`
    /// turns them into "waiting to join" and "expired, hasn't joined".
    func recentInvites(familyId: UUID) async throws -> [PendingInvite] {
        // Filtered client-side rather than with IS NULL / > filters so this
        // only uses query builders already exercised elsewhere in the app.
        // Unused invites are kept 30 days past expiry (00058), so the window
        // stays small.
        try await supabase
            .from("invite_tokens")
            .select("id, name, phone, role, token, checkin_time, pairing_code, created_at, expires_at, used_by")
            .eq("family_id", value: familyId.uuidString)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value
    }

    /// A fixed past instant for a cancelled invite. Not the device clock: a
    /// phone set behind would write a time still in the server's future and
    /// leave the "cancelled" link working. Also lets the app tell a
    /// cancellation from a natural expiry.
    static let cancelledExpiry = "2000-01-01T00:00:00Z"

    /// Cancel an invite: its link and setup code stop working at once. Expires
    /// it rather than deleting it, so the record of what was sent remains.
    func cancelInvite(id: UUID) async throws {
        try await supabase
            .from("invite_tokens")
            .update(["expires_at": Self.cancelledExpiry])
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Hand the family to an active co-caregiver. Uses
    /// transfer_family_ownership_v2 (00058), which refuses a receiver and
    /// keeps the caller as a viewer even without a membership row. On a server
    /// without it, falls back to the 00045 function; the app only offers
    /// viewers as targets, so the fallback is asked the same thing.
    func transferOwnership(familyId: UUID, to newOwnerUserId: UUID) async throws {
        let params = [
            "p_family_id": familyId.uuidString,
            "p_new_owner_user_id": newOwnerUserId.uuidString,
        ]
        do {
            try await supabase.rpc("transfer_family_ownership_v2", params: params).execute()
        } catch let error where Self.isMissingFunction(error) {
            try await supabase.rpc("transfer_family_ownership", params: params).execute()
        }
    }

    /// A receiver or co-caregiver leaves the family (00061 leave_family): the
    /// membership ends, pending check-ins stand down, and the owner's
    /// dashboard gets a "left the family" alert. Throws when the server
    /// predates the function (`isMissingFunction`) — the caller then says to
    /// ask the owner instead.
    func leaveFamily(familyId: UUID) async throws {
        try await supabase
            .rpc("leave_family", params: ["p_family_id": familyId.uuidString])
            .execute()
    }

    /// PostgREST "function not found" (PGRST202) or Postgres 42883.
    nonisolated static func isMissingFunction(_ error: Error) -> Bool {
        let text = "\(error) \(error.localizedDescription)"
        return text.contains("PGRST202") || text.contains("42883")
            || text.contains("Could not find the function")
    }

    /// Withdraw an invite that was created but never sent.
    func cancelInvite(token: String) async throws {
        try await supabase
            .from("invite_tokens")
            .update(["expires_at": Self.cancelledExpiry])
            .eq("token", value: token)
            .execute()
    }

    /// Remove someone from the family. Throws `.notPermitted` when RLS let the
    /// request through but changed nothing (ownership moved, already gone),
    /// which used to look like success.
    func removeMember(memberId: UUID) async throws {
        struct IdRow: Decodable { let id: UUID }
        let rows: [IdRow] = try await supabase
            .from("family_members")
            .update(["status": MemberStatus.deactivated.rawValue])
            .eq("id", value: memberId.uuidString)
            .select("id")
            .execute()
            .value
        if rows.isEmpty { throw FamilyError.notPermitted }
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
        return JoinDetails(
            checkinTime: response.checkinTime,
            ownerName: response.ownerName,
            role: response.role.flatMap(UserRole.init(rawValue:))
        )
    }

    /// Describe the family an invite link joins, WITHOUT joining (the
    /// optional `preview` field). A server that predates it ignores the field
    /// and joins at once; that answer comes back as `.joined`.
    func previewInvite(token: String) async throws -> JoinStep {
        let response: JoinPreviewResponse = try await EdgeFunctionsClient.invoke(
            "invite-receiver",
            json: [
                "action": .string("accept"),
                "token": .string(token),
                "timezone": .string(TimeZone.current.identifier),
                "preview": .bool(true),
            ]
        )
        return response.step
    }

    /// Redeem a 6-digit pairing code (iPad / alternate-device setup).
    /// Returns the join result from the server.
    func redeemPairingCode(_ code: String) async throws -> RedeemCodeResponse {
        try await EdgeFunctionsClient.invoke(
            "redeem-code",
            body: ["code": code, "timezone": TimeZone.current.identifier]
        )
    }

    /// Check a code and describe its family WITHOUT joining. Counts toward the
    /// same server lockout as a redeem. A server that predates `preview` joins
    /// at once; the response then carries `success` instead of `preview`.
    func previewPairingCode(_ code: String) async throws -> RedeemCodeResponse {
        try await EdgeFunctionsClient.invoke(
            "redeem-code",
            json: [
                "code": .string(code),
                "timezone": .string(TimeZone.current.identifier),
                "preview": .bool(true),
            ]
        )
    }

    /// Check if the authenticated user's verified phone matches a pending
    /// invite. With `preview`, nothing is joined yet (the app asks first); an
    /// older server ignores the flag and joins, which comes back as a match
    /// with `isPreview == false`.
    ///
    /// `familyId` (optional; older servers ignore it) limits the join to the
    /// family the preview showed.
    func checkAutoJoin(preview: Bool = false, familyId: String? = nil) async throws -> AutoJoinCheck {
        // The device zone lets the server schedule check-ins at the receiver's
        // local time from the first day (optional field; older servers ignore it).
        var body: [String: JSONValue] = ["timezone": .string(TimeZone.current.identifier)]
        if preview { body["preview"] = .bool(true) }
        if let familyId { body["family_id"] = .string(familyId) }
        let data: AutoJoinResponse = try await EdgeFunctionsClient.invoke("auto-join", json: body)
        return data.check
    }
}

/// What asking auto-join produced.
enum AutoJoinCheck {
    /// The verified phone matches an invite.
    case matched(AutoJoinResult)
    /// It matches, but the family can't take them (plan full); the server's
    /// explanation is attached.
    case blocked(String)
    case noMatch
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
    /// Who the invite is for, as the owner typed it.
    var name: String? = nil
    var role: UserRole = .receiver
    /// The invite's secret, so an invite that was never sent can be withdrawn.
    var token: String? = nil

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

/// A row of invite_tokens as the owner sees it: sent, and maybe used.
struct PendingInvite: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String?
    let phone: String?
    /// nil only if the column wasn't selected; the table default is receiver.
    var role: UserRole? = nil
    /// The link's secret. Lets the app rebuild the link and its QR code.
    var token: String? = nil
    /// Postgres TIME, e.g. "08:30:00".
    let checkinTime: String?
    let pairingCode: String?
    let createdAt: Date
    let expiresAt: Date
    let usedBy: UUID?

    /// Receiver unless the row says viewer.
    var invitedRole: UserRole { role == .viewer ? .viewer : .receiver }

    /// The link the invite text carried (same format as the server's
    /// buildInviteLink), or nil without a token.
    var inviteLink: String? {
        guard let token, !token.isEmpty else { return nil }
        var link = "https://dailyok.net/invite/\(token)"
        if let code = pairingCode, !code.isEmpty { link += "?code=\(code)" }
        return link
    }

    enum CodingKeys: String, CodingKey {
        case id, name, phone, role, token
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
    /// Echoed by servers that understand co-caregiver invites (additive).
    let role: String?

    enum CodingKeys: String, CodingKey {
        case success, role
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
    // Additive: a `preview: true` answer (nothing joined yet).
    var preview: Bool? = nil
    var familyName: String? = nil
    var inviteName: String? = nil
    var watchers: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case success, preview, watchers
        case alreadyMember = "already_member"
        case familyId = "family_id"
        case role
        case checkinTime = "checkin_time"
        case name
        case ownerName = "owner_name"
        case familyName = "family_name"
        case inviteName = "invite_name"
        case error
    }

    /// The role joined (or that would be joined). An already-member answer
    /// carries the member's real role, which can be owner (their own
    /// family's code); it used to be flattened to receiver.
    var joinedRole: UserRole {
        role.flatMap(UserRole.init(rawValue:)) ?? .receiver
    }

    /// Set when this is a preview answer.
    var joinPreview: JoinPreview? {
        guard preview == true, let familyId, !familyId.isEmpty else { return nil }
        return JoinPreview(
            familyId: familyId,
            familyName: familyName,
            role: role == UserRole.viewer.rawValue ? .viewer : .receiver,
            ownerName: ownerName,
            inviteName: inviteName,
            checkinTime: checkinTime,
            watchers: watchers ?? [],
            alreadyMember: alreadyMember == true
        )
    }
}

struct AutoJoinResponse: Decodable {
    let matched: Bool
    let alreadyMember: Bool?
    let familyId: String?
    let role: String?
    let checkinTime: String?
    let ownerName: String?
    // Additive fields: `preview` answers, and why a match couldn't join.
    var preview: Bool? = nil
    var familyName: String? = nil
    var inviteName: String? = nil
    var watchers: [String]? = nil
    var reason: String? = nil
    var message: String? = nil

    enum CodingKeys: String, CodingKey {
        case matched, preview, watchers, reason, message
        case alreadyMember = "already_member"
        case familyId = "family_id"
        case role
        case checkinTime = "checkin_time"
        case ownerName = "owner_name"
        case familyName = "family_name"
        case inviteName = "invite_name"
    }

    var check: AutoJoinCheck {
        if !matched {
            if reason == "limit_reached" {
                return .blocked(message ?? String(localized: "This family's plan has no free places. Ask the person who invited you to make room, then try again."))
            }
            return .noMatch
        }
        // A match with no family_id is not actionable — emitting an empty
        // string would just make a downstream UUID(uuidString:) fail.
        guard let familyId, !familyId.isEmpty else { return .noMatch }
        return .matched(AutoJoinResult(
            familyId: familyId,
            role: role ?? "receiver",
            checkinTime: checkinTime,
            ownerName: ownerName,
            isPreview: preview == true,
            familyName: familyName,
            inviteName: inviteName,
            watchers: watchers ?? [],
            alreadyMember: alreadyMember == true
        ))
    }
}

struct AutoJoinResult: Equatable {
    let familyId: String
    let role: String
    let checkinTime: String?
    var ownerName: String? = nil
    /// Nothing is joined yet: the app must ask before confirming.
    var isPreview: Bool = false
    var familyName: String? = nil
    var inviteName: String? = nil
    var watchers: [String] = []
    var alreadyMember: Bool = false

    var joinPreview: JoinPreview {
        JoinPreview(
            familyId: familyId,
            familyName: familyName,
            role: role == UserRole.viewer.rawValue ? .viewer : .receiver,
            ownerName: ownerName,
            inviteName: inviteName,
            checkinTime: checkinTime,
            watchers: watchers,
            alreadyMember: alreadyMember
        )
    }
}

/// What joining a family would mean, shown BEFORE anything is redeemed:
/// whose family, as what, and who will see this person's check-ins.
struct JoinPreview: Equatable {
    let familyId: String
    let familyName: String?
    /// .receiver or .viewer (co-caregiver).
    let role: UserRole
    let ownerName: String?
    /// What the owner called the invitee ("Mom").
    let inviteName: String?
    let checkinTime: String?
    /// The owner, then active co-caregivers (placeholder names left out).
    let watchers: [String]
    let alreadyMember: Bool

    /// A name fit to show: nil for empty and for the "User" placeholder that
    /// phone / Apple sign-ups get when no name was given.
    static func presentableName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed != "User" else { return nil }
        return trimmed
    }

    var displayOwnerName: String? { Self.presentableName(ownerName) }

    /// "Sarah", "Sarah and Tom", "Sarah, Tom, and Ann" — everyone who will
    /// see the check-ins; nil when no one has a real name yet.
    var watchersList: String? {
        var names = watchers.compactMap { Self.presentableName($0) }
        if names.isEmpty, let owner = displayOwnerName { names = [owner] }
        guard !names.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: names)
    }

    /// The headline question: "Join Sarah's family?"
    var headline: String {
        if let owner = displayOwnerName {
            return String(localized: "Join \(owner)'s family?")
        }
        if let family = Self.presentableName(familyName) {
            return String(localized: "Join \(family)?")
        }
        return String(localized: "Join this family?")
    }

    /// Who will see what, in one sentence.
    var sharingSentence: String {
        let who = watchersList ?? String(localized: "The family who invited you")
        if role == .viewer {
            return String(localized: "You'll join as a co-caregiver. \(who) and you will be told if a check-in is missed, and you'll see everyone's check-ins and their location when shared.")
        }
        return String(localized: "\(who) will see when you check in each day, your phone's battery level, and your location if you choose to share it.")
    }
}

/// Where a preview-capable request left things.
enum JoinStep: Equatable {
    /// Nothing joined yet.
    case preview(JoinPreview)
    /// An older server joined at once (it ignores `preview`).
    case joined(JoinDetails)
}

/// Raw decode of a `preview: true` answer from invite-receiver accept (or its
/// join answer from a server that predates previews).
struct JoinPreviewResponse: Decodable {
    let preview: Bool?
    let familyId: String?
    let familyName: String?
    let role: String?
    let ownerName: String?
    let inviteName: String?
    let checkinTime: String?
    let watchers: [String]?
    let alreadyMember: Bool?

    enum CodingKeys: String, CodingKey {
        case preview, role, watchers
        case familyId = "family_id"
        case familyName = "family_name"
        case ownerName = "owner_name"
        case inviteName = "invite_name"
        case checkinTime = "checkin_time"
        case alreadyMember = "already_member"
    }

    var step: JoinStep {
        let joinedRole: UserRole = role == UserRole.viewer.rawValue ? .viewer : .receiver
        guard preview == true, let familyId, !familyId.isEmpty else {
            return .joined(JoinDetails(checkinTime: checkinTime, ownerName: ownerName, role: joinedRole))
        }
        return .preview(JoinPreview(
            familyId: familyId,
            familyName: familyName,
            role: joinedRole,
            ownerName: ownerName,
            inviteName: inviteName,
            checkinTime: checkinTime,
            watchers: watchers ?? [],
            alreadyMember: alreadyMember == true
        ))
    }
}

/// What a successful join tells the receiver's onboarding screen.
struct JoinDetails: Equatable {
    let checkinTime: String?
    let ownerName: String?
    /// The role joined as (nil against an older backend: a receiver).
    var role: UserRole? = nil
}

/// Raw decode of a successful invite-receiver accept.
struct JoinDetailsResponse: Decodable {
    let checkinTime: String?
    let ownerName: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case checkinTime = "checkin_time"
        case ownerName = "owner_name"
        case role
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
    /// The server predates co-caregiver invites; the invite was withdrawn.
    case caregiverInvitesUnavailable
    /// The write was allowed through but changed nothing.
    case notPermitted

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in"
        case .familyNotFound: return "Family not found"
        case .memberLimitReached: return "You've reached the maximum number of members for your plan"
        case .notPermitted:
            return "Nothing was changed — you may no longer manage this family. Pull down to refresh."
        case .caregiverInvitesUnavailable:
            return "Co-caregiver invites aren't available yet. Nothing was sent — please try again after the next update."
        }
    }
}
