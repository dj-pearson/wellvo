package net.dailyok.android.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A check-in request as the caregiver dashboard needs it: status, escalation
 * and who (if anyone) has said "I'm on it".
 *
 * Every field past the 00001 core is optional so a server without 00055
 * (stood_down_*) or 00062 (claimed_*) still decodes; statuses are kept as
 * strings so a value added later can't fail the whole list.
 */
@Serializable
data class OpenCheckInRequest(
    val id: String,
    @SerialName("family_id")
    val familyId: String,
    @SerialName("receiver_id")
    val receiverId: String,
    val status: String,
    @SerialName("created_at")
    val createdAt: String,
    @SerialName("escalation_step")
    val escalationStep: Int = 0,
    @SerialName("next_escalation_at")
    val nextEscalationAt: String? = null,
    @SerialName("stood_down_at")
    val stoodDownAt: String? = null,
    @SerialName("claimed_by")
    val claimedBy: String? = null,
    @SerialName("claimed_at")
    val claimedAt: String? = null,
    @SerialName("claimed_by_name")
    val claimedByName: String? = null
) {
    val isMissed: Boolean get() = status == "missed"
    val isPending: Boolean get() = status == "pending"
}

/** Who has taken on an alert: the part of the row `acknowledge_alert_v2` returns that the app uses. */
@Serializable
data class AlertClaim(
    val id: String,
    @SerialName("acknowledged_by")
    val acknowledgedBy: String? = null,
    @SerialName("acknowledged_at")
    val acknowledgedAt: String? = null,
    @SerialName("acknowledged_by_name")
    val acknowledgedByName: String? = null
)
