package net.dailyok.android.services

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.exception.PostgrestRestException
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.put
import net.dailyok.android.data.models.AlertClaim
import net.dailyok.android.data.models.OpenCheckInRequest
import net.dailyok.android.network.ApiService
import net.dailyok.android.network.CancelEscalationRequest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * What the owner and co-caregivers do about a missed check-in or a help
 * request: see who is on it, say "I'm on it", stop the alerts, check on now.
 *
 * Co-caregivers use the same calls as the owner. The server decides who may:
 * claim_checkin_request / acknowledge_alert_v2 accept any active owner or
 * co-caregiver; cancel-escalation and on-demand-checkin are being opened to
 * co-caregivers server-side, and until then answer 403 with a message the
 * app shows as is.
 */
@Singleton
class CaregiverActionsService @Inject constructor(
    private val supabase: SupabaseClient,
    private val apiService: ApiService
) {
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    /**
     * Pending or missed check-in requests in this family from the last two
     * days, newest first. `select *` rather than named columns so a server
     * without the 00055 / 00062 columns still answers.
     */
    suspend fun openRequests(familyId: String): List<OpenCheckInRequest> {
        val since = java.time.Instant.now().minus(java.time.Duration.ofHours(48)).toString()
        val result = supabase.postgrest.from("checkin_requests")
            .select {
                filter { eq("family_id", familyId) }
                filter { isIn("status", listOf("pending", "missed")) }
                filter { gte("created_at", since) }
                order("created_at", Order.DESCENDING)
                limit(50)
            }
        return decodeList(result.data)
    }

    /**
     * "I'm on it" for a missed / escalating check-in, or [release] it
     * (claim_checkin_request, 00062). Returns the row as it now stands, so the
     * caller sees who actually holds the claim.
     */
    suspend fun claimRequest(requestId: String, release: Boolean): OpenCheckInRequest? {
        val result = supabase.postgrest.rpc(
            "claim_checkin_request",
            buildJsonObject {
                put("p_request_id", requestId)
                put("p_release", release)
            }
        )
        return decodeSingle(result.data)
    }

    /**
     * "I'm on it" for a help alert, or [release] it. acknowledge_alert_v2
     * (00055) only claims an unclaimed alert; v1 is used only when v2 is
     * missing (a pre-00055 backend), never after another failure.
     */
    suspend fun acknowledgeAlert(alertId: String, release: Boolean): AlertClaim? {
        val params = buildJsonObject {
            put("p_alert_id", alertId)
            put("p_release", release)
        }
        val result = try {
            supabase.postgrest.rpc("acknowledge_alert_v2", params)
        } catch (e: Exception) {
            if (!isMissingFunction(e)) throw e
            supabase.postgrest.rpc("acknowledge_alert", params)
        }
        return decodeSingle(result.data)
    }

    /** Stop the escalation for this receiver's open check-in (no check-in is recorded). */
    suspend fun stopAlerts(familyId: String, receiverId: String) {
        apiService.cancelEscalation(CancelEscalationRequest(receiverId = receiverId, familyId = familyId))
    }

    private fun decodeList(raw: String): List<OpenCheckInRequest> {
        val element = runCatching { json.parseToJsonElement(raw) }.getOrNull() as? JsonArray ?: return emptyList()
        return element.mapNotNull { runCatching { json.decodeFromJsonElement<OpenCheckInRequest>(it) }.getOrNull() }
    }

    private inline fun <reified T> decodeSingle(raw: String): T? {
        val element: JsonElement = runCatching { json.parseToJsonElement(raw) }.getOrNull() ?: return null
        val row = if (element is JsonArray) element.firstOrNull() ?: return null else element
        return runCatching { json.decodeFromJsonElement<T>(row) }.getOrNull()
    }

    companion object {
        /** PostgREST "function not found" (PGRST202) or Postgres 42883. */
        fun isMissingFunction(e: Throwable): Boolean {
            val code = (e as? PostgrestRestException)?.code
            if (code == "PGRST202" || code == "42883") return true
            val text = listOfNotNull(e.message, (e as? RestException)?.error).joinToString(" ")
            return text.contains("PGRST202") || text.contains("42883") ||
                text.contains("Could not find the function")
        }
    }
}
