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

    /// Returns the current user's role in their family, or nil if they have no membership.
    /// Used on login to route receivers/viewers to the correct UI without requiring re-onboarding.
    func getCurrentUserRole() async -> UserRole? {
        guard let session = try? await supabase.auth.session else { return nil }

        // If the user owns any family, they are an owner. This takes precedence
        // over any receiver/viewer memberships they may also hold (e.g. if the
        // same account was invited into another family for testing).
        let ownedFamilies: [Family] = (try? await supabase
            .from("families")
            .select("id")
            .eq("owner_id", value: session.user.id.uuidString)
            .limit(1)
            .execute()
            .value) ?? []

        if !ownedFamilies.isEmpty {
            return .owner
        }

        let members: [FamilyMember] = (try? await supabase
            .from("family_members")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .eq("status", value: MemberStatus.active.rawValue)
            .limit(1)
            .execute()
            .value) ?? []

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

    func inviteReceiver(familyId: UUID, name: String, phone: String, checkinTime: String) async throws {
        try await EdgeFunctionsClient.invoke(
            "invite-receiver",
            body: [
                "family_id": familyId.uuidString,
                "name": name,
                "phone": phone,
                "checkin_time": checkinTime,
            ]
        )
    }

    func removeMember(memberId: UUID) async throws {
        try await supabase
            .from("family_members")
            .update(["status": MemberStatus.deactivated.rawValue])
            .eq("id", value: memberId.uuidString)
            .execute()
    }

    func acceptInvite(token: String) async throws {
        try await EdgeFunctionsClient.invoke(
            "invite-receiver",
            body: [
                "action": "accept",
                "token": token,
            ]
        )
    }

    /// Redeem a 6-digit pairing code (iPad / alternate-device setup).
    /// Returns the join result from the server.
    func redeemPairingCode(_ code: String) async throws -> RedeemCodeResponse {
        try await EdgeFunctionsClient.invoke(
            "redeem-code",
            body: ["code": code]
        )
    }

    /// Check if the authenticated user's phone matches a pending invite and auto-join.
    /// Returns the auto-join result, or nil if no match found.
    func checkAutoJoin() async throws -> AutoJoinResult? {
        let data: AutoJoinResponse = try await EdgeFunctionsClient.invoke("auto-join", body: [:])

        // A match with no family_id is not actionable — emitting an empty string
        // would just make a downstream UUID(uuidString:) fail. Treat it as "no
        // match" instead.
        guard data.matched, let familyId = data.familyId, !familyId.isEmpty else { return nil }

        return AutoJoinResult(
            familyId: familyId,
            role: data.role ?? "receiver",
            checkinTime: data.checkinTime
        )
    }
}

struct RedeemCodeResponse: Decodable {
    let success: Bool?
    let alreadyMember: Bool?
    let familyId: String?
    let role: String?
    let checkinTime: String?
    let name: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case alreadyMember = "already_member"
        case familyId = "family_id"
        case role
        case checkinTime = "checkin_time"
        case name
        case error
    }
}

struct AutoJoinResponse: Decodable {
    let matched: Bool
    let alreadyMember: Bool?
    let familyId: String?
    let role: String?
    let checkinTime: String?

    enum CodingKeys: String, CodingKey {
        case matched
        case alreadyMember = "already_member"
        case familyId = "family_id"
        case role
        case checkinTime = "checkin_time"
    }
}

struct AutoJoinResult {
    let familyId: String
    let role: String
    let checkinTime: String?
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
