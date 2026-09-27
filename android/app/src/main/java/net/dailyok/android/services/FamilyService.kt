package net.dailyok.android.services

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import net.dailyok.android.data.models.Family
import net.dailyok.android.data.models.FamilyMember
import net.dailyok.android.data.models.UserRole
import net.dailyok.android.network.ApiService
import net.dailyok.android.network.AutoJoinResult
import net.dailyok.android.network.InviteReceiverRequest
import net.dailyok.android.network.RedeemCodeResponse
import net.dailyok.android.network.DailyOKError
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FamilyService @Inject constructor(
    private val supabase: SupabaseClient,
    private val apiService: ApiService
) {
    suspend fun createFamily(name: String): Family {
        val userId = supabase.auth.currentUserOrNull()?.id
            ?: throw DailyOKError.Auth("Not signed in.")

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
        } catch (e: DailyOKError) {
            throw e
        } catch (e: Exception) {
            throw DailyOKError.Unknown(e.message ?: "Failed to create family.")
        }
    }

    suspend fun getFamily(userId: String): Family? {
        try {
            // Earliest join wins — keeps owner + receiver apps agreeing on the
            // same family when stray duplicates exist in the DB.
            val member = supabase.postgrest.from("family_members")
                .select {
                    filter { eq("user_id", userId) }
                    filter { eq("status", "active") }
                    order("joined_at", Order.ASCENDING)
                    limit(1)
                }
                .decodeList<FamilyMember>()
                .firstOrNull()
                ?: return null

            return supabase.postgrest.from("families")
                .select {
                    filter { eq("id", member.familyId) }
                }
                .decodeSingleOrNull<Family>()
        } catch (e: Exception) {
            throw DailyOKError.Unknown(e.message ?: "Failed to fetch family.")
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
            throw DailyOKError.Unknown(e.message ?: "Failed to fetch family members.")
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
            throw DailyOKError.Unknown(e.message ?: "Failed to get user role.")
        }
    }

    suspend fun inviteReceiver(
        familyId: String,
        name: String,
        phone: String,
        checkinTime: String,
        receiverMode: String = "standard",
        /** "receiver" or "viewer" (co-caregiver). */
        role: String = "receiver"
    ): net.dailyok.android.util.InviteToSend {
        try {
            val response = apiService.inviteReceiver(
                InviteReceiverRequest(
                    familyId = familyId,
                    phone = phone,
                    displayName = name,
                    receiverMode = receiverMode,
                    checkinTime = checkinTime,
                    role = role
                )
            )
            if (role == "viewer" && response.role != "viewer") {
                // A server without co-caregiver invites made a receiver
                // invite instead. Sending it would sign this person up for
                // daily check-ins, so don't.
                throw DailyOKError.Unknown("Co-caregiver invites aren't available yet. Please try again later.")
            }
            return net.dailyok.android.util.InviteToSend(
                phone = phone,
                message = net.dailyok.android.util.InviteShare.message(
                    name, response.inviteLink, response.pairingCode, response.inviteMessage
                ),
                pairingCode = response.pairingCode
            )
        } catch (e: DailyOKError) {
            throw e
        } catch (e: Exception) {
            throw DailyOKError.Unknown(e.message ?: "Failed to invite receiver.")
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
            throw DailyOKError.Unknown(e.message ?: "Failed to remove member.")
        }
    }

    /**
     * Redeem an invite link. It used to send receiver_mode "accept:<token>"
     * to the create path, which the server rejected, so links never joined.
     */
    suspend fun acceptInvite(token: String): net.dailyok.android.network.JoinResponse {
        try {
            return apiService.acceptInvite(token)
        } catch (e: DailyOKError) {
            throw e
        } catch (e: Exception) {
            throw DailyOKError.Unknown(e.message ?: "Failed to accept invite.")
        }
    }

    suspend fun redeemPairingCode(code: String): RedeemCodeResponse {
        try {
            return apiService.redeemCode(code)
        } catch (e: DailyOKError) {
            throw e
        } catch (e: Exception) {
            throw DailyOKError.Unknown(e.message ?: "Failed to redeem code.")
        }
    }

    suspend fun checkAutoJoin(phone: String): AutoJoinResult? {
        try {
            val response = apiService.autoJoin()
            return apiService.checkAutoJoinResult(response)
        } catch (e: DailyOKError) {
            throw e
        } catch (e: Exception) {
            throw DailyOKError.Unknown(e.message ?: "Failed to check auto-join.")
        }
    }

    /**
     * Hand the family to an active co-caregiver, in one transaction on the
     * server: transfer_family_ownership_v2 (00058) refuses a receiver and
     * keeps the caller in the family as a co-caregiver. Only a server without
     * v2 falls back to the 00045 function (asked the same thing; the app only
     * offers co-caregivers).
     *
     * This replaces three separate client writes, which set families.owner_id
     * to the *membership row id* (not a user id) and could stop half way.
     */
    suspend fun transferOwnership(newOwnerUserId: String, familyId: String) {
        if (supabase.auth.currentUserOrNull()?.id == null) throw DailyOKError.Auth("Not signed in.")
        val params = buildJsonObject {
            put("p_family_id", familyId)
            put("p_new_owner_user_id", newOwnerUserId)
        }
        try {
            try {
                supabase.postgrest.rpc("transfer_family_ownership_v2", params)
            } catch (e: Exception) {
                if (!CaregiverActionsService.isMissingFunction(e)) throw e
                supabase.postgrest.rpc("transfer_family_ownership", params)
            }
        } catch (e: DailyOKError) {
            throw e
        } catch (e: Exception) {
            throw DailyOKError.Unknown(serverMessage(e) ?: "Couldn't transfer ownership. Please try again.")
        }
    }

    /**
     * A co-caregiver (or receiver) leaves the family (leave_family, 00061):
     * membership ends, their "I'm on it" claims are released (00062) and the
     * owner gets a "left the family" notice. The owner can't leave; they
     * transfer the family first.
     */
    suspend fun leaveFamily(familyId: String) {
        try {
            supabase.postgrest.rpc("leave_family", buildJsonObject { put("p_family_id", familyId) })
        } catch (e: Exception) {
            if (CaregiverActionsService.isMissingFunction(e)) {
                throw DailyOKError.Unknown("Leaving isn't available yet. Ask the family owner to remove you.")
            }
            throw DailyOKError.Unknown(serverMessage(e) ?: "Couldn't leave the family. Please try again.")
        }
    }

    /** The Postgres exception text (e.g. "Ownership can only go to a co-caregiver"), if any. */
    private fun serverMessage(e: Exception): String? =
        (e as? io.github.jan.supabase.exceptions.RestException)?.error?.takeIf { it.isNotBlank() }
}
