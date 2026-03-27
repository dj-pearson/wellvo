package net.wellvo.android.network

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class CheckInResponseRequest(
    val requestId: String,
    val mood: String? = null,
    val source: String = "app",
    val latitude: Double? = null,
    val longitude: Double? = null,
    val locationAccuracyMeters: Double? = null,
    val kidResponseType: String? = null
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
    val receiverMode: String = "standard"
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
    val checkinTime: String? = null
)

data class AutoJoinResult(
    val familyId: String,
    val role: String,
    val checkinTime: String?
)

private val json = Json { ignoreUnknownKeys = true }

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
                    body = body
                )
                val statusCode = response.status.value
                val responseBody = response.body<String>()

                when {
                    statusCode in 200..299 -> responseBody
                    statusCode == 401 || statusCode == 403 -> throw WellvoError.Auth()
                    statusCode == 404 -> throw WellvoError.NotFound()
                    statusCode in 500..599 -> throw WellvoError.ServerError()
                    else -> throw WellvoError.Unknown("Unexpected status: $statusCode")
                }
            } catch (e: WellvoError) {
                throw e
            } catch (e: java.net.UnknownHostException) {
                throw WellvoError.Offline()
            } catch (e: java.net.SocketTimeoutException) {
                throw WellvoError.Network("Request timed out.")
            } catch (e: Exception) {
                throw WellvoError.Network(e.message ?: "Network error")
            }
        }
    }

    suspend fun processCheckinResponse(request: CheckInResponseRequest): String {
        return invokeFunction("process-checkin-response", buildJsonObject {
            put("request_id", request.requestId)
            request.mood?.let { put("mood", it) }
            put("source", request.source)
            request.latitude?.let { put("latitude", it) }
            request.longitude?.let { put("longitude", it) }
            request.locationAccuracyMeters?.let { put("location_accuracy_meters", it) }
            request.kidResponseType?.let { put("kid_response_type", it) }
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
            put("request_id", request.requestId)
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

    suspend fun inviteReceiver(request: InviteReceiverRequest): String {
        return invokeFunction("invite-receiver", buildJsonObject {
            put("family_id", request.familyId)
            put("phone", request.phone)
            put("display_name", request.displayName)
            put("receiver_mode", request.receiverMode)
        })
    }

    suspend fun redeemCode(code: String): RedeemCodeResponse {
        val responseBody = invokeFunction("redeem-code", buildJsonObject {
            put("code", code)
        })
        return json.decodeFromString<RedeemCodeResponse>(responseBody)
    }

    suspend fun autoJoin(): AutoJoinResponse {
        val responseBody = invokeFunction("auto-join", buildJsonObject { })
        return json.decodeFromString<AutoJoinResponse>(responseBody)
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
