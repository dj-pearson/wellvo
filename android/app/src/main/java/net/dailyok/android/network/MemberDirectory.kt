package net.dailyok.android.network

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.exception.PostgrestRestException
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import net.dailyok.android.data.models.AppUser

/**
 * Reads of people's `users` rows that respect what each caller may see
 * (migration 00067).
 *
 * Other members' email, phone and is_system_admin are not for clients: member
 * lists select [AppUser.MEMBER_COLUMNS], phone numbers come from
 * `family_contact_numbers`, and your own full row from `get_my_profile`. A
 * staged migration then revokes column SELECT on those columns, which binds
 * your own row too, so self-reads must not go through the table.
 */
object MemberDirectory {

    @Serializable
    private data class ContactRow(
        @SerialName("user_id") val userId: String,
        val phone: String? = null
    )

    @Serializable
    private data class LegacyPhoneRow(val id: String, val phone: String? = null)

    /**
     * The signed-in user's own profile, every column, or null when there is
     * no profile row yet. Throws when the lookup fails. A server without
     * `get_my_profile` yet gets the same columns from the table.
     */
    suspend fun myProfile(supabase: SupabaseClient, userId: String): AppUser? {
        return try {
            supabase.postgrest.rpc("get_my_profile").decodeList<AppUser>().firstOrNull()
        } catch (e: Exception) {
            if (!isMissingFunction(e)) throw e
            supabase.postgrest.from("users")
                .select(columns = Columns.raw(AppUser.SELF_COLUMNS)) {
                    filter { eq("id", userId) }
                    limit(1)
                }
                .decodeList<AppUser>()
                .firstOrNull()
        }
    }

    /**
     * Phone numbers the caller may see, by user id: every active member's for
     * an owner or co-caregiver, the caregivers' only for a receiver, plus
     * your own. [familyId] null means every family you're in. Throws when
     * the lookup fails.
     *
     * On a server without `family_contact_numbers` (00067 not applied yet)
     * it reads users.phone for [userIds] directly. That works until the
     * staged column revoke lands, which waits for every supported build to
     * have this code.
     */
    suspend fun contactNumbers(
        supabase: SupabaseClient,
        familyId: String?,
        userIds: List<String>
    ): Map<String, String> {
        try {
            val params = buildJsonObject { if (familyId != null) put("p_family_id", familyId) }
            return supabase.postgrest.rpc("family_contact_numbers", params)
                .decodeList<ContactRow>()
                .mapNotNull { row -> row.phone?.trim()?.takeIf { it.isNotEmpty() }?.let { row.userId to it } }
                .toMap()
        } catch (e: Exception) {
            if (!isMissingFunction(e)) throw e
        }
        if (userIds.isEmpty()) return emptyMap()
        return supabase.postgrest.from("users")
            .select(columns = Columns.list("id", "phone")) {
                filter { isIn("id", userIds) }
            }
            .decodeList<LegacyPhoneRow>()
            .mapNotNull { row -> row.phone?.trim()?.takeIf { it.isNotEmpty() }?.let { row.id to it } }
            .toMap()
    }

    /** [contactNumbers], but a failed lookup gives no numbers instead of throwing. */
    suspend fun contactNumbersOrEmpty(
        supabase: SupabaseClient,
        familyId: String?,
        userIds: List<String>
    ): Map<String, String> = try {
        contactNumbers(supabase, familyId, userIds)
    } catch (_: Exception) {
        emptyMap()
    }

    /** PostgREST's "function not found" (PGRST202): a server without the RPC yet. */
    fun isMissingFunction(e: Throwable): Boolean {
        if ((e as? PostgrestRestException)?.code == "PGRST202") return true
        val text = listOfNotNull(e.message, (e as? RestException)?.error).joinToString(" ")
        return text.contains("could not find the function", ignoreCase = true)
    }
}
