package net.dailyok.android.data.models

import androidx.compose.runtime.Immutable
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

@Immutable
@Serializable
data class DailyOKAlert(
    val id: String,
    @SerialName("family_id")
    val familyId: String,
    @SerialName("receiver_id")
    val receiverId: String,
    val type: String,
    val title: String,
    val message: String,
    /**
     * Free-form server payload. Was Map<String, Double>, which failed to
     * decode any alert carrying text (member_left has "role", help alerts
     * carry labels) — and one such row emptied the whole alert list.
     * Read numbers through [number].
     */
    val data: JsonElement? = null,
    @SerialName("is_read")
    val isRead: Boolean,
    @SerialName("created_at")
    val createdAt: String,
    /** Who said "I'm on it" (acknowledge_alert_v2, 00055). */
    @SerialName("acknowledged_by")
    val acknowledgedBy: String? = null,
    @SerialName("acknowledged_at")
    val acknowledgedAt: String? = null,
    @SerialName("acknowledged_by_name")
    val acknowledgedByName: String? = null
) {
    /** Someone may need help now: can be taken on with "I'm on it". */
    val isUrgent: Boolean get() = type in URGENT_TYPES

    /** A numeric field of [data] ("drift_hours"), or null. */
    fun number(key: String): Double? =
        ((data as? JsonObject)?.get(key) as? JsonPrimitive)?.doubleOrNull

    companion object {
        val URGENT_TYPES = setOf("need_help", "call_me", "sos", "geofence_breach")
    }
}
