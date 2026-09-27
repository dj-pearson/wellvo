package net.dailyok.android.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FamilyTextTest {

    @Test
    fun `caregiver texts greet by first name and match the state`() {
        val pending = FamilyText.checkingOn("Margaret Smith", missed = false)
        assertTrue(pending.startsWith("Hi Margaret,"))
        assertTrue(pending.contains("All good?"))
        assertTrue(FamilyText.checkingOn("Mom", missed = true).contains("make sure you're OK"))
        assertTrue(FamilyText.helpReply("Mom", callMe = true).contains("like a call"))
        assertTrue(FamilyText.helpReply("Mom", callMe = false).contains("I'm on it"))
    }

    @Test
    fun `alert text follows the push type`() {
        assertTrue(FamilyText.forAlertType("Mom", "viewer_alert").contains("check-in"))
        assertTrue(FamilyText.forAlertType("Mom", "owner_alert").contains("check-in"))
        assertTrue(FamilyText.forAlertType("Mom", "call_me").contains("like a call"))
        assertTrue(FamilyText.forAlertType("Mom", "need_help").contains("help alert"))
    }

    @Test
    fun `help text adds an approximate location only when known`() {
        assertEquals(
            "Hi Sarah, I need help. Please call me as soon as you can.",
            FamilyText.askingForHelp("Sarah Jones", callMe = false)
        )
        val located = FamilyText.askingForHelp(null, callMe = false, latitude = 40.712776, longitude = -74.005974)
        assertTrue(located.startsWith("I need help."))
        assertTrue(located.contains("https://maps.google.com/?q=40.713,-74.006"))
        assertTrue(FamilyText.askingForHelp(null, callMe = true).startsWith("Can you call me"))
        assertNull(FamilyText.approximateMapLink(0.0, 0.0))
        assertNull(FamilyText.approximateMapLink(null, 1.0))
    }

    @Test
    fun `dialable keeps digits and plus`() {
        assertEquals("+15551234567", FamilyText.dialable("+1 (555) 123-4567"))
        assertNull(FamilyText.dialable(""))
        assertNull(FamilyText.dialable(null))
    }
}
