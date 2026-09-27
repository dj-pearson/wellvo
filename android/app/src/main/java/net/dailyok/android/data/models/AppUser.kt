package net.dailyok.android.data.models

import androidx.compose.runtime.Immutable
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Immutable
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
) {
    companion object {
        /**
         * Columns for OTHER people's users rows (member lists, embeds). Never
         * `*`: email, phone and is_system_admin are not for other members
         * (00067; column SELECT on them is revoked by a staged migration).
         * Phone numbers come from MemberDirectory.contactNumbers.
         */
        const val MEMBER_COLUMNS =
            "id, display_name, role, avatar_url, timezone, created_at, updated_at, last_seen_at, last_battery_level, last_app_version"

        /** Your own row through the table, for a server without get_my_profile(). */
        const val SELF_COLUMNS = "$MEMBER_COLUMNS, email, phone"
    }
}

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
