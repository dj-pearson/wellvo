package net.dailyok.android.viewmodels

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StopAlertsCopyTest {

    @Test
    fun `owner confirmation does not mention telling anyone`() {
        val text = CareStatus.stopAlertsConfirmMessage("Mom", isCoCaregiver = false, ownerName = "Sarah")
        assertEquals("Only do this if you've confirmed Mom is OK. It stops the reminders and caregiver alerts.", text)
    }

    @Test
    fun `co-caregiver confirmation says the care team is told`() {
        val named = CareStatus.stopAlertsConfirmMessage("Mom", isCoCaregiver = true, ownerName = "Sarah")
        assertTrue(named.endsWith("Sarah and the other caregivers will be told you stopped them."))
        val unnamed = CareStatus.stopAlertsConfirmMessage("Mom", isCoCaregiver = true, ownerName = " ")
        assertTrue(unnamed.endsWith("The family owner and the other caregivers will be told you stopped them."))
    }

    @Test
    fun `done message differs for owner and co-caregiver`() {
        val owner = CareStatus.stopAlertsDoneMessage("Mom", isCoCaregiver = false, ownerName = null)
        assertEquals("Alerts stopped for Mom. Their check-in stays open until they answer.", owner)
        assertFalse(owner.contains("told"))
        val co = CareStatus.stopAlertsDoneMessage("Mom", isCoCaregiver = true, ownerName = "Sarah")
        assertTrue(co.endsWith("Sarah and the other caregivers were told you stopped them."))
    }
}
