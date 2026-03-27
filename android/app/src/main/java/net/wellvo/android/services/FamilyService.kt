package net.wellvo.android.services

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import net.wellvo.android.data.models.Family
import net.wellvo.android.data.models.FamilyMember
import net.wellvo.android.data.models.UserRole
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.AutoJoinResult
import net.wellvo.android.network.InviteReceiverRequest
import net.wellvo.android.network.RedeemCodeResponse
import net.wellvo.android.network.WellvoError
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FamilyService @Inject constructor(
    private val supabase: SupabaseClient,
    private val apiService: ApiService
) {
    suspend fun createFamily(name: String): Family {
        val userId = supabase.auth.currentUserOrNull()?.id
            ?: throw WellvoError.Auth("Not signed in.")

        try {
            val family = supabase.postgrest.from("families")
                .insert(buildJsonObject {
                    put("name", name)
                    put("owner_id", userId)
                }) {
                    select()
                }
                .decodeSingle<Family>()

            supabase.postgrest.from("family_members")
                .insert(buildJsonObject {
                    put("family_id", family.id)
                    put("user_id", userId)
                    put("role", "owner")
                    put("status", "active")
                })

            return family
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to create family.")
        }
    }

    suspend fun getFamily(userId: String): Family? {
        try {
            val member = supabase.postgrest.from("family_members")
                .select {
                    filter { eq("user_id", userId) }
                    filter { eq("status", "active") }
                }
                .decodeSingleOrNull<FamilyMember>()
                ?: return null

            return supabase.postgrest.from("families")
                .select {
                    filter { eq("id", member.familyId) }
                }
                .decodeSingleOrNull<Family>()
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to fetch family.")
        }
    }

    suspend fun getFamilyMembers(familyId: String): List<FamilyMember> {
        try {
            return supabase.postgrest.from("family_members")
                .select(columns = Columns.raw("*, users(*)")) {
                    filter { eq("family_id", familyId) }
                }
                .decodeList<FamilyMember>()
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to fetch family members.")
        }
    }

    suspend fun getCurrentUserRole(userId: String, familyId: String): UserRole? {
        try {
            val member = supabase.postgrest.from("family_members")
                .select {
                    filter { eq("user_id", userId) }
                    filter { eq("family_id", familyId) }
                    filter { eq("status", "active") }
                }
                .decodeSingleOrNull<FamilyMember>()
            return member?.role
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to get user role.")
        }
    }

    suspend fun inviteReceiver(
        familyId: String,
        name: String,
        phone: String,
        checkinTime: String,
        receiverMode: String = "standard"
    ) {
        try {
            apiService.inviteReceiver(
                InviteReceiverRequest(
                    familyId = familyId,
                    phone = phone,
                    displayName = name,
                    receiverMode = receiverMode
                )
            )
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to invite receiver.")
        }
    }

    suspend fun removeMember(memberId: String) {
        try {
            supabase.postgrest.from("family_members")
                .update(buildJsonObject {
                    put("status", "deactivated")
                }) {
                    filter { eq("id", memberId) }
                }
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to remove member.")
        }
    }

    suspend fun acceptInvite(token: String) {
        try {
            apiService.inviteReceiver(
                InviteReceiverRequest(
                    familyId = "",
                    phone = "",
                    displayName = "",
                    receiverMode = "accept:$token"
                )
            )
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to accept invite.")
        }
    }

    suspend fun redeemPairingCode(code: String): RedeemCodeResponse {
        try {
            return apiService.redeemCode(code)
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to redeem code.")
        }
    }

    suspend fun checkAutoJoin(phone: String): AutoJoinResult? {
        try {
            val response = apiService.autoJoin()
            return apiService.checkAutoJoinResult(response)
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to check auto-join.")
        }
    }

    suspend fun transferOwnership(memberId: String, familyId: String) {
        try {
            val currentUserId = supabase.auth.currentUserOrNull()?.id
                ?: throw WellvoError.Auth("Not signed in.")

            // Update the target member to owner
            supabase.postgrest.from("family_members")
                .update(buildJsonObject {
                    put("role", "owner")
                }) {
                    filter { eq("id", memberId) }
                }

            // Update current user to viewer
            supabase.postgrest.from("family_members")
                .update(buildJsonObject {
                    put("role", "viewer")
                }) {
                    filter { eq("user_id", currentUserId) }
                    filter { eq("family_id", familyId) }
                }

            // Update family owner_id
            supabase.postgrest.from("families")
                .update(buildJsonObject {
                    put("owner_id", memberId)
                }) {
                    filter { eq("id", familyId) }
                }
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to transfer ownership.")
        }
    }
}
