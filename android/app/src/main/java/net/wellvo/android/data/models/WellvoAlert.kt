package net.wellvo.android.data.models

import androidx.compose.runtime.Immutable
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Immutable
@Serializable
data class WellvoAlert(
    val id: String,
    @SerialName("family_id")
    val familyId: String,
    @SerialName("receiver_id")
    val receiverId: String,
    val type: String,
    val title: String,
    val message: String,
    val data: Map<String, Double>? = null,
    @SerialName("is_read")
    val isRead: Boolean,
    @SerialName("created_at")
    val createdAt: String
)
