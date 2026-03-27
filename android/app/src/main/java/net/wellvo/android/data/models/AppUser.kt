package net.wellvo.android.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AppUser(
    val id: String,
    val email: String? = null,
    val phone: String? = null,
    @SerialName("display_name")
    val displayName: String,
    val role: UserRole,
    @SerialName("avatar_url")
    val avatarUrl: String? = null,
    val timezone: String,
    @SerialName("created_at")
    val createdAt: String,
    @SerialName("updated_at")
    val updatedAt: String,
    @SerialName("last_seen_at")
    val lastSeenAt: String? = null,
    @SerialName("last_battery_level")
    val lastBatteryLevel: Double? = null,
    @SerialName("last_app_version")
    val lastAppVersion: String? = null
)

@Serializable
enum class UserRole {
    @SerialName("owner") Owner,
    @SerialName("receiver") Receiver,
    @SerialName("viewer") Viewer
}

@Serializable
enum class MemberStatus {
    @SerialName("active") Active,
    @SerialName("invited") Invited,
    @SerialName("deactivated") Deactivated
}
