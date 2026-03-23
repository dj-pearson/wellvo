import Foundation
import Supabase

actor FamilyService {
    static let shared = FamilyService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    func createFamily(name: String) async throws -> Family {
        guard let session = try? await supabase.auth.session else {
            throw FamilyError.notAuthenticated
        }

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

        let families: [Family] = try await supabase
            .from("families")
            .select()
            .or("owner_id.eq.\(session.user.id.uuidString)")
            .limit(1)
            .execute()
            .value

        if let family = families.first { return family }

        // Check if user is a member of a family
        let memberships: [FamilyMember] = try await supabase
            .from("family_members")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .eq("status", value: MemberStatus.active.rawValue)
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
        try await supabase.functions.invoke(
            "invite-receiver",
            options: .init(body: [
                "family_id": familyId.uuidString,
                "name": name,
                "phone": phone,
                "checkin_time": checkinTime,
            ])
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
        try await supabase.functions.invoke(
            "invite-receiver",
            options: .init(body: [
                "action": "accept",
                "token": token,
            ])
        )
    }

    /// Redeem a 6-digit pairing code (iPad / alternate-device setup).
    /// Returns the join result from the server.
    func redeemPairingCode(_ code: String) async throws -> RedeemCodeResponse {
        let data: RedeemCodeResponse = try await supabase.functions.invoke(
            "redeem-code",
            options: .init(body: ["code": code])
        )
        return data
    }

    /// Check if the authenticated user's phone matches a pending invite and auto-join.
    /// Returns the auto-join result, or nil if no match found.
    func checkAutoJoin() async throws -> AutoJoinResult? {
        let data: AutoJoinResponse = try await supabase.functions.invoke(
            "auto-join",
            options: .init(body: [:] as [String: String])
        )

        guard data.matched else { return nil }

        return AutoJoinResult(
            familyId: data.familyId ?? "",
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
