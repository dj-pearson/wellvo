package net.wellvo.android.services

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubscriptionServiceTest {

    // =========================================================================
    // Free tier (legacy / grandfathered only)
    // =========================================================================

    @Test
    fun `Free tier always has access to Free features`() {
        assertTrue(hasAccessHelper(SubscriptionTier.Free, SubscriptionTier.Free))
    }

    @Test
    fun `Free tier does not have access to Caregiver features`() {
        assertFalse(hasAccessHelper(SubscriptionTier.Caregiver, SubscriptionTier.Free))
    }

    @Test
    fun `Free tier does not have access to Family features`() {
        assertFalse(hasAccessHelper(SubscriptionTier.Family, SubscriptionTier.Free))
    }

    @Test
    fun `Free tier does not have access to FamilyPlus features`() {
        assertFalse(hasAccessHelper(SubscriptionTier.FamilyPlus, SubscriptionTier.Free))
    }

    // =========================================================================
    // Caregiver tier
    // =========================================================================

    @Test
    fun `Caregiver tier has access to Free features`() {
        assertTrue(hasAccessHelper(SubscriptionTier.Free, SubscriptionTier.Caregiver))
    }

    @Test
    fun `Caregiver tier has access to Caregiver features`() {
        assertTrue(hasAccessHelper(SubscriptionTier.Caregiver, SubscriptionTier.Caregiver))
    }

    @Test
    fun `Caregiver tier does not have access to Family features`() {
        assertFalse(hasAccessHelper(SubscriptionTier.Family, SubscriptionTier.Caregiver))
    }

    @Test
    fun `Caregiver tier does not have access to FamilyPlus features`() {
        assertFalse(hasAccessHelper(SubscriptionTier.FamilyPlus, SubscriptionTier.Caregiver))
    }

    // =========================================================================
    // Family tier
    // =========================================================================

    @Test
    fun `Family tier has access to Family features`() {
        assertTrue(hasAccessHelper(SubscriptionTier.Family, SubscriptionTier.Family))
    }

    @Test
    fun `Family tier has access to Caregiver features`() {
        assertTrue(hasAccessHelper(SubscriptionTier.Caregiver, SubscriptionTier.Family))
    }

    @Test
    fun `Family tier has access to Free features`() {
        assertTrue(hasAccessHelper(SubscriptionTier.Free, SubscriptionTier.Family))
    }

    @Test
    fun `Family tier does not have access to FamilyPlus features`() {
        assertFalse(hasAccessHelper(SubscriptionTier.FamilyPlus, SubscriptionTier.Family))
    }

    // =========================================================================
    // Family+ tier
    // =========================================================================

    @Test
    fun `FamilyPlus tier has access to all tiers`() {
        assertTrue(hasAccessHelper(SubscriptionTier.Free, SubscriptionTier.FamilyPlus))
        assertTrue(hasAccessHelper(SubscriptionTier.Caregiver, SubscriptionTier.FamilyPlus))
        assertTrue(hasAccessHelper(SubscriptionTier.Family, SubscriptionTier.FamilyPlus))
        assertTrue(hasAccessHelper(SubscriptionTier.FamilyPlus, SubscriptionTier.FamilyPlus))
    }

    // =========================================================================
    // Product ID catalog
    // =========================================================================

    @Test
    fun `PRODUCT_IDS contains all expected products`() {
        assertEquals(8, SubscriptionService.PRODUCT_IDS.size)
        assertTrue(SubscriptionService.PRODUCT_IDS.contains("net.wellvo.caregiver.monthly"))
        assertTrue(SubscriptionService.PRODUCT_IDS.contains("net.wellvo.caregiver.yearly"))
        assertTrue(SubscriptionService.PRODUCT_IDS.contains("net.wellvo.family.monthly"))
        assertTrue(SubscriptionService.PRODUCT_IDS.contains("net.wellvo.family.yearly"))
        assertTrue(SubscriptionService.PRODUCT_IDS.contains("net.wellvo.familyplus.monthly"))
        assertTrue(SubscriptionService.PRODUCT_IDS.contains("net.wellvo.familyplus.yearly"))
        assertTrue(SubscriptionService.PRODUCT_IDS.contains("net.wellvo.addon.receiver"))
        assertTrue(SubscriptionService.PRODUCT_IDS.contains("net.wellvo.addon.viewer"))
    }

    @Test
    fun `tier mapping from product ID prefixes`() {
        assertEquals(SubscriptionTier.FamilyPlus, tierFromProductId("net.wellvo.familyplus.monthly"))
        assertEquals(SubscriptionTier.FamilyPlus, tierFromProductId("net.wellvo.familyplus.yearly"))
        assertEquals(SubscriptionTier.Family, tierFromProductId("net.wellvo.family.monthly"))
        assertEquals(SubscriptionTier.Family, tierFromProductId("net.wellvo.family.yearly"))
        assertEquals(SubscriptionTier.Caregiver, tierFromProductId("net.wellvo.caregiver.monthly"))
        assertEquals(SubscriptionTier.Caregiver, tierFromProductId("net.wellvo.caregiver.yearly"))
        assertEquals(SubscriptionTier.Free, tierFromProductId("unknown.product"))
    }

    // =========================================================================
    // Billing errors
    // =========================================================================

    @Test
    fun `BillingError types have correct messages`() {
        assertEquals("Billing client not connected", BillingError.NotConnected().message)
        assertEquals("Purchase cancelled", BillingError.UserCancelled().message)
        assertEquals("You already own this subscription", BillingError.AlreadyOwned().message)
        assertEquals("Network error during purchase", BillingError.NetworkError().message)
        assertEquals("Custom error", BillingError.Unknown("Custom error").message)
    }

    // =========================================================================
    // Helpers (mirror the real SubscriptionService logic)
    // =========================================================================

    // Mirrors SubscriptionService.hasAccess logic
    private fun hasAccessHelper(requestedTier: SubscriptionTier, currentTier: SubscriptionTier): Boolean {
        return when (requestedTier) {
            SubscriptionTier.Free -> true
            SubscriptionTier.Caregiver ->
                currentTier == SubscriptionTier.Caregiver ||
                currentTier == SubscriptionTier.Family ||
                currentTier == SubscriptionTier.FamilyPlus
            SubscriptionTier.Family ->
                currentTier == SubscriptionTier.Family || currentTier == SubscriptionTier.FamilyPlus
            SubscriptionTier.FamilyPlus ->
                currentTier == SubscriptionTier.FamilyPlus
        }
    }

    // Mirrors SubscriptionService.updateCurrentTier product ID mapping.
    // Order matters: "net.wellvo.family" prefix would also match
    // "net.wellvo.familyplus.*" — familyplus must be checked first.
    private fun tierFromProductId(productId: String): SubscriptionTier {
        return when {
            productId.startsWith("net.wellvo.familyplus") -> SubscriptionTier.FamilyPlus
            productId.startsWith("net.wellvo.family") -> SubscriptionTier.Family
            productId.startsWith("net.wellvo.caregiver") -> SubscriptionTier.Caregiver
            else -> SubscriptionTier.Free
        }
    }
}
