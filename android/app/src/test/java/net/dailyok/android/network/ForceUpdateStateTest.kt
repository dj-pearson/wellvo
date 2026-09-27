package net.dailyok.android.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ForceUpdateStateTest {

    @Test
    fun `versions compare like the server`() {
        assertTrue(ForceUpdateState.compareVersions("1.0.10", "1.0.9") > 0)
        assertEquals(0, ForceUpdateState.compareVersions("1.0", "1.0.0"))
        assertEquals(0, ForceUpdateState.compareVersions("1.0.0-debug", "1.0.0"))
        assertTrue(ForceUpdateState.compareVersions("1.0.6", "1.0.7") < 0)
    }

    @Test
    fun `floor is dormant until raised`() {
        assertFalse(ForceUpdateState.isBelowMinimum("1.0.0", "0.0.0"))
        assertFalse(ForceUpdateState.isBelowMinimum("1.0.0", null))
        assertFalse(ForceUpdateState.isBelowMinimum("1.0.0", ""))
        assertTrue(ForceUpdateState.isBelowMinimum("1.0.0", "1.0.1"))
        assertFalse(ForceUpdateState.isBelowMinimum("1.0.1", "1.0.1"))
    }
}
