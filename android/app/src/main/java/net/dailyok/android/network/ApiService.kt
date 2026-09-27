package net.dailyok.android.network

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class CheckInResponseRequest(
    val requestId: String? = null,
    val receiverId: String? = null,
    val familyId: String? = null,
    val mood: String? = null,
    val source: String = "app",
    val latitude: Double? = null,
    val longitude: Double? = null,
    val locationAccuracyMeters: Double? = null,
    val kidResponseType: String? = null,
    /** "ok" (default server-side), "need_help" or "call_me". */
    val responseType: String? = null,
    /** 0.0–1.0; the owner sees it with the check-in. */
    val batteryLevel: Double? = null,
    /**
     * RFC 3339 instant the check-in was actually made, for a check-in replayed
     * from the offline queue (US-IOS147). Null for a live check-in, where the
     * server's now() is the same instant.
     */
    val occurredAt: String? = null,
    /** Where a kid says they are ("school", "friends_house"); shown with a help alert. */
    val locationLabel: String? = null
)

@Serializable
data class OnDemandCheckinRequest(
    val receiverId: String,
    val familyId: String
)

@Serializable
data class ConfirmDeliveryRequest(
    val requestId: String
)

@Serializable
data class HeartbeatRequest(
    val batteryLevel: Double? = null,
    val appVersion: String? = null
)

@Serializable
data class ReportLocationRequest(
    val familyId: String,
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Double? = null
)

@Serializable
data class InviteReceiverRequest(
    val familyId: String,
    val phone: String,
    val displayName: String,
    val receiverMode: String = "standard",
    /** "HH:mm", 24-hour. */
    val checkinTime: String? = null,
    /**
     * "receiver" (someone to check on; the default and all older builds send)
     * or "viewer" (a co-caregiver: alerts, no check-ins). Optional server
     * field on invite-receiver (edge pass 4).
     */
    val role: String = "receiver"
)

/** What invite-receiver returns on create: everything the owner sends. */
@Serializable
data class InviteResponse(
    val success: Boolean? = null,
    @kotlinx.serialization.SerialName("invite_link")
    val inviteLink: String? = null,
    @kotlinx.serialization.SerialName("pairing_code")
    val pairingCode: String? = null,
    @kotlinx.serialization.SerialName("invite_message")
    val inviteMessage: String? = null,
    /**
     * The role the server stored. Absent from a server that predates
     * co-caregiver invites, which made a receiver invite whatever was asked.
     */
    val role: String? = null
)

@Serializable
data class CancelEscalationRequest(
    val receiverId: String,
    val familyId: String
)

/** A successful join (accept / redeem-code). */
@Serializable
data class JoinResponse(
    val success: Boolean? = null,
    @kotlinx.serialization.SerialName("family_id")
    val familyId: String? = null,
    val role: String? = null,
    @kotlinx.serialization.SerialName("checkin_time")
    val checkinTime: String? = null,
    @kotlinx.serialization.SerialName("owner_name")
    val ownerName: String? = null
)

@Serializable
data class RedeemCodeResponse(
    val success: Boolean? = null,
    @kotlinx.serialization.SerialName("already_member")
    val alreadyMember: Boolean? = null,
    @kotlinx.serialization.SerialName("family_id")
    val familyId: String? = null,
    val role: String? = null,
    @kotlinx.serialization.SerialName("checkin_time")
    val checkinTime: String? = null,
    val name: String? = null,
    val error: String? = null
)

@Serializable
data class AutoJoinResponse(
    val matched: Boolean,
    @kotlinx.serialization.SerialName("already_member")
    val alreadyMember: Boolean? = null,
    @kotlinx.serialization.SerialName("family_id")
    val familyId: String? = null,
    val role: String? = null,
    @kotlinx.serialization.SerialName("checkin_time")
    val checkinTime: String? = null,
    /** Why nothing was joined ("limit_reached", "no_matching_invite", …). */
    val reason: String? = null
)

data class AutoJoinResult(
    val familyId: String,
    val role: String,
    val checkinTime: String?,
    /**
     * Set when this is an invite waiting for the person's "Join" (auto-join
     * preview), not a join that already happened.
     */
    val preview: JoinPreview? = null
)

private val json = Json { ignoreUnknownKeys = true }

/**
 * Sent with every edge call so the server can enforce
 * MIN_SUPPORTED_ANDROID_APP_VERSION (426 force-update). Builds without these
 * headers are never gated (the server fails open).
 */
private val clientHeaders: Headers = Headers.build {
    append("X-App-Version", net.dailyok.android.BuildConfig.VERSION_NAME)
    append("X-App-Platform", "android")
}

@Singleton
class ApiService @Inject constructor(
    private val supabase: SupabaseClient
) {
    private suspend fun invokeFunction(
        functionName: String,
        body: JsonObject
    ): String {
        return withRetry {
            try {
                val response = supabase.functions.invoke(
                    function = functionName,
                    body = body,
                    headers = clientHeaders
                )
                val statusCode = response.status.value
                val responseBody = response.body<String>()

                when {
                    statusCode in 200..299 -> responseBody
                    statusCode == 426 -> throw updateRequired(responseBody)
                    statusCode == 401 || statusCode == 403 -> throw DailyOKError.Auth()
                    statusCode == 404 -> throw DailyOKError.NotFound()
                    statusCode in 500..599 -> throw DailyOKError.ServerError()
                    else -> throw DailyOKError.Unknown("Unexpected status: $statusCode")
                }
            } catch (e: DailyOKError) {
                throw e
            } catch (e: RestException) {
                // supabase-kt throws for any non-2xx before the status checks
                // above run, and its message carries the request URL and
                // headers — which the old catch-all showed to users as a
                // "network error". Use the function's own "error" text.
                throw rejection(e.statusCode, e.error)
            } catch (e: java.net.UnknownHostException) {
                throw DailyOKError.Offline()
            } catch (e: java.net.SocketTimeoutException) {
                throw DailyOKError.Network("Request timed out.")
            } catch (e: Exception) {
                throw DailyOKError.Network(e.message ?: "Network error")
            }
        }
    }

    /**
     * 426: this build is below MIN_SUPPORTED_ANDROID_APP_VERSION. Latches the
     * app-wide blocking update screen; never retried.
     */
    private fun updateRequired(body: String?): DailyOKError {
        ForceUpdateState.triggerFromResponse(body)
        return DailyOKError.Rejected(426, "Please update Daily OK to keep using it.")
    }

    private fun rejection(status: Int, body: String): DailyOKError {
        if (status == 426) return updateRequired(body)
        val serverMessage = runCatching {
            json.parseToJsonElement(body).jsonObject["error"]?.jsonPrimitive?.contentOrNull
        }.getOrNull()
        return when (status) {
            401 -> DailyOKError.Auth()
            in 500..599 -> DailyOKError.ServerError()
            429 -> DailyOKError.Rejected(status, serverMessage ?: "Too many attempts. Please wait and try again.")
            else -> DailyOKError.Rejected(status, serverMessage ?: "Something went wrong. Please try again.")
        }
    }

    suspend fun processCheckinResponse(request: CheckInResponseRequest): String {
        // The edge function accepts either `checkin_request_id` (notification
        // response path) or `receiver_id` + `family_id` (manual check-in
        // without a pending request). Send whichever the caller provided.
        return invokeFunction("process-checkin-response", buildJsonObject {
            request.requestId?.let { put("checkin_request_id", it) }
            request.receiverId?.let { put("receiver_id", it) }
            request.familyId?.let { put("family_id", it) }
            request.mood?.let { put("mood", it) }
            put("source", request.source)
            request.latitude?.let { put("latitude", it) }
            request.longitude?.let { put("longitude", it) }
            request.locationAccuracyMeters?.let { put("location_accuracy_meters", it) }
            request.kidResponseType?.let { put("kid_response_type", it) }
            // Without response_type the server records "ok": "I Need Help"
            // and "Call Me" from a notification were logged as fine and no
            // urgent alert reached the owner.
            request.responseType?.let { put("response_type", it) }
            request.batteryLevel?.let { put("battery_level", it) }
            // US-IOS147. Without this the server stamps checked_in_at with
            // now(), so a check-in queued Monday and synced Thursday is
            // recorded as a Thursday check-in nobody made and the owner's
            // dashboard reads "checked in today" for someone who has not
            // touched their phone in three days.
            request.occurredAt?.let { put("occurred_at", it) }
            request.locationLabel?.let { put("location_label", it) }
        })
    }

    suspend fun onDemandCheckin(request: OnDemandCheckinRequest): String {
        return invokeFunction("on-demand-checkin", buildJsonObject {
            put("receiver_id", request.receiverId)
            put("family_id", request.familyId)
        })
    }

    suspend fun confirmDelivery(request: ConfirmDeliveryRequest): String {
        return invokeFunction("confirm-delivery", buildJsonObject {
            put("checkin_request_id", request.requestId)
        })
    }

    suspend fun heartbeat(request: HeartbeatRequest): String {
        return invokeFunction("heartbeat", buildJsonObject {
            request.batteryLevel?.let { put("battery_level", it) }
            request.appVersion?.let { put("app_version", it) }
        })
    }

    suspend fun reportLocation(request: ReportLocationRequest): String {
        return invokeFunction("report-location", buildJsonObject {
            put("family_id", request.familyId)
            put("latitude", request.latitude)
            put("longitude", request.longitude)
            request.accuracyMeters?.let { put("accuracy_meters", it) }
        })
    }

    suspend fun inviteReceiver(request: InviteReceiverRequest): InviteResponse {
        // The server requires `name` (it never read display_name, so every
        // Android invite was a 400) and uses checkin_time / timezone.
        val responseBody = invokeFunction("invite-receiver", buildJsonObject {
            put("family_id", request.familyId)
            put("phone", request.phone)
            put("name", request.displayName)
            put("display_name", request.displayName)
            put("receiver_mode", request.receiverMode)
            // A co-caregiver has no schedule (the server drops one anyway).
            if (request.role != "viewer") request.checkinTime?.let { put("checkin_time", it) }
            put("timezone", java.time.ZoneId.systemDefault().id)
            // Sent only for a co-caregiver, so a receiver invite is byte for
            // byte the request older servers have always had.
            if (request.role == "viewer") put("role", "viewer")
        })
        return json.decodeFromString<InviteResponse>(responseBody)
    }

    /** Redeem an invite link's token (invite-receiver, action "accept"). */
    suspend fun acceptInvite(token: String): JoinResponse {
        val responseBody = invokeFunction("invite-receiver", buildJsonObject {
            put("action", "accept")
            put("token", token)
            put("timezone", java.time.ZoneId.systemDefault().id)
        })
        return json.decodeFromString<JoinResponse>(responseBody)
    }

    suspend fun redeemCode(code: String): RedeemCodeResponse {
        val responseBody = invokeFunction("redeem-code", buildJsonObject {
            put("code", code)
            put("timezone", java.time.ZoneId.systemDefault().id)
        })
        return json.decodeFromString<RedeemCodeResponse>(responseBody)
    }

    /**
     * Join the family whose invite matches this account's verified phone.
     * [familyId] (optional server field) pins the join to the family the user
     * was just shown in the preview, so "Join" can't land in a different
     * family that invited the same number in between.
     */
    suspend fun autoJoin(familyId: String? = null): AutoJoinResponse {
        val responseBody = invokeFunction("auto-join", buildJsonObject {
            put("timezone", java.time.ZoneId.systemDefault().id)
            familyId?.let { put("family_id", it) }
        })
        return json.decodeFromString<AutoJoinResponse>(responseBody)
    }

    // --- Ask before joining (optional `preview: true`, edge pass 6) ---------
    // A server without `preview` ignores it and joins at once. Its answer then
    // has no `preview: true`, and JoinPreviews.interpret reports AlreadyJoined.

    /** Describe the family behind an invite link without joining it. */
    suspend fun previewInvite(token: String): JoinPreview {
        val responseBody = invokeFunction("invite-receiver", buildJsonObject {
            put("action", "accept")
            put("token", token)
            put("preview", true)
            put("timezone", java.time.ZoneId.systemDefault().id)
        })
        return json.decodeFromString<JoinPreview>(responseBody)
    }

    /** Describe the family behind a 6-digit setup code without joining it. */
    suspend fun previewCode(code: String): JoinPreview {
        val responseBody = invokeFunction("redeem-code", buildJsonObject {
            put("code", code)
            put("preview", true)
            put("timezone", java.time.ZoneId.systemDefault().id)
        })
        return json.decodeFromString<JoinPreview>(responseBody)
    }

    /** Describe the family whose invite matches this phone, without joining it. */
    suspend fun previewAutoJoin(): JoinPreview {
        val responseBody = invokeFunction("auto-join", buildJsonObject {
            put("preview", true)
            put("timezone", java.time.ZoneId.systemDefault().id)
        })
        return json.decodeFromString<JoinPreview>(responseBody)
    }

    /**
     * Stop the escalation for a receiver's open check-in without recording a
     * check-in (the caregiver reached them another way).
     */
    suspend fun cancelEscalation(request: CancelEscalationRequest): String {
        return invokeFunction("cancel-escalation", buildJsonObject {
            put("receiver_id", request.receiverId)
            put("family_id", request.familyId)
        })
    }

    fun checkAutoJoinResult(response: AutoJoinResponse): AutoJoinResult? {
        if (!response.matched) return null
        return AutoJoinResult(
            familyId = response.familyId ?: "",
            role = response.role ?: "receiver",
            checkinTime = response.checkinTime
        )
    }

    suspend fun subscriptionWebhook(payload: JsonObject): String {
        return invokeFunction("subscription-webhook", payload)
    }
}
