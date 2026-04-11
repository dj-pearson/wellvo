package net.wellvo.android.data.models

import androidx.compose.runtime.Immutable
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Immutable
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
    // Grandfathering deadline for legacy Free-tier families. When set and in
    // the past, clients should gate paid features and prompt the Owner to
    // upgrade to Caregiver. NULL for families created after the Caregiver
    // tier migration.
    @SerialName("free_tier_expires_at")
    val freeTierExpiresAt: String? = null,
    @SerialName("max_receivers")
    val maxReceivers: Int,
    @SerialName("max_viewers")
    val maxViewers: Int,
    @SerialName("created_at")
    val createdAt: String
)

@Serializable
enum class SubscriptionTier {
    // Legacy tier, kept for grandfathered families created before the
    // Caregiver tier launched. New signups never land here.
    @SerialName("free") Free,
    // Lowest paid tier, sized for 1 Receiver + 3 Viewers (the dementia-
    // caregiver persona). $3.99/mo or $29.99/yr.
    @SerialName("caregiver") Caregiver,
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

@Immutable
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
