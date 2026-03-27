package net.wellvo.android.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Family(
    val id: String,
    val name: String,
    @SerialName("owner_id")
    val ownerId: String,
    @SerialName("subscription_tier")
    val subscriptionTier: SubscriptionTier,
    @SerialName("subscription_status")
    val subscriptionStatus: SubscriptionStatus,
    @SerialName("subscription_expires_at")
    val subscriptionExpiresAt: String? = null,
    @SerialName("max_receivers")
    val maxReceivers: Int,
    @SerialName("max_viewers")
    val maxViewers: Int,
    @SerialName("created_at")
    val createdAt: String
)

@Serializable
enum class SubscriptionTier {
    @SerialName("free") Free,
    @SerialName("family") Family,
    @SerialName("family_plus") FamilyPlus
}

@Serializable
enum class SubscriptionStatus {
    @SerialName("active") Active,
    @SerialName("expired") Expired,
    @SerialName("grace_period") GracePeriod,
    @SerialName("cancelled") Cancelled
}

@Serializable
data class FamilyMember(
    val id: String,
    @SerialName("family_id")
    val familyId: String,
    @SerialName("user_id")
    val userId: String,
    val role: UserRole,
    val status: MemberStatus,
    @SerialName("invited_at")
    val invitedAt: String? = null,
    @SerialName("joined_at")
    val joinedAt: String? = null,
    @SerialName("users")
    val user: AppUser? = null
)
