package net.wellvo.android.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CheckIn(
    val id: String,
    @SerialName("receiver_id")
    val receiverId: String,
    @SerialName("family_id")
    val familyId: String,
    @SerialName("checked_in_at")
    val checkedInAt: String,
    val mood: Mood? = null,
    val source: CheckInSource,
    @SerialName("scheduled_for")
    val scheduledFor: String? = null,
    @SerialName("response_type")
    val responseType: CheckInResponseType? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    @SerialName("location_accuracy_meters")
    val locationAccuracyMeters: Double? = null,
    @SerialName("distance_from_home_meters")
    val distanceFromHomeMeters: Double? = null,
    @SerialName("location_label")
    val locationLabel: String? = null,
    @SerialName("kid_response_type")
    val kidResponseType: String? = null
)

@Serializable
enum class Mood {
    @SerialName("happy") Happy,
    @SerialName("neutral") Neutral,
    @SerialName("tired") Tired,
    @SerialName("excited") Excited,
    @SerialName("bored") Bored,
    @SerialName("hungry") Hungry,
    @SerialName("scared") Scared,
    @SerialName("having_fun") HavingFun
}

@Serializable
enum class CheckInSource {
    @SerialName("app") App,
    @SerialName("notification") Notification,
    @SerialName("on_demand") OnDemand,
    @SerialName("need_help") NeedHelp,
    @SerialName("call_me") CallMe
}

@Serializable
enum class CheckInResponseType {
    @SerialName("ok") Ok,
    @SerialName("need_help") NeedHelp,
    @SerialName("call_me") CallMe
}

@Serializable
data class CheckInRequest(
    val id: String,
    @SerialName("family_id")
    val familyId: String,
    @SerialName("receiver_id")
    val receiverId: String,
    @SerialName("requested_by")
    val requestedBy: String,
    val type: CheckInRequestType,
    val status: CheckInRequestStatus,
    @SerialName("created_at")
    val createdAt: String,
    @SerialName("responded_at")
    val respondedAt: String? = null,
    @SerialName("escalation_step")
    val escalationStep: Int,
    @SerialName("next_escalation_at")
    val nextEscalationAt: String? = null
)

@Serializable
enum class CheckInRequestStatus {
    @SerialName("pending") Pending,
    @SerialName("checked_in") CheckedIn,
    @SerialName("missed") Missed,
    @SerialName("expired") Expired
}

@Serializable
enum class CheckInRequestType {
    @SerialName("scheduled") Scheduled,
    @SerialName("on_demand") OnDemand
}
