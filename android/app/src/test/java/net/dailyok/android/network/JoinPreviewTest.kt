package net.dailyok.android.network

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class JoinPreviewTest {
    private val json = Json { ignoreUnknownKeys = true }

    private fun decode(raw: String): JoinPreview = json.decodeFromString(raw)

    @Test
    fun `a preview answer asks first and names the role`() {
        val outcome = JoinPreviews.interpret(decode(
            """{"preview":true,"family_id":"f1","family_name":"The Smiths","role":"viewer",
               "owner_name":"Sarah","invite_name":"Tom","checkin_time":null,
               "watchers":["Sarah","User"," "],"already_member":false}"""
        ))
        assertTrue(outcome is JoinPreviewOutcome.AskFirst)
        val preview = (outcome as JoinPreviewOutcome.AskFirst).preview
        assertTrue(preview.isViewer)
        assertEquals("Join Sarah's family?", JoinPreviews.title(preview))
        // "User" placeholders and blanks are not names.
        assertEquals("Caring together with Sarah.", JoinPreviews.watchersLine(preview))
    }

    @Test
    fun `auto-join preview carries matched and preview`() {
        val outcome = JoinPreviews.interpret(decode(
            """{"matched":true,"preview":true,"family_id":"f1","role":"receiver","owner_name":"Sarah","checkin_time":"08:30:00","watchers":[]}"""
        ))
        val preview = (outcome as JoinPreviewOutcome.AskFirst).preview
        assertEquals(
            "Sarah will ask you to tap \"I'm OK\" each day around 8:30 AM. If you don't, they'll be told.",
            JoinPreviews.explanation(preview)
        )
        assertNull(JoinPreviews.watchersLine(preview))
    }

    @Test
    fun `already a member never asks`() {
        val outcome = JoinPreviews.interpret(decode(
            """{"preview":true,"family_id":"f1","role":"owner","already_member":true}"""
        ))
        assertEquals(JoinPreviewOutcome.AlreadyJoined("f1", "owner"), outcome)
    }

    @Test
    fun `an older server that ignored preview has already joined`() {
        // invite-receiver accept / redeem-code
        assertEquals(
            JoinPreviewOutcome.AlreadyJoined("f1", "viewer"),
            JoinPreviews.interpret(decode("""{"success":true,"family_id":"f1","role":"viewer","checkin_time":null}"""))
        )
        // auto-join
        assertEquals(
            JoinPreviewOutcome.AlreadyJoined("f2", "receiver"),
            JoinPreviews.interpret(decode("""{"matched":true,"family_id":"f2","role":"receiver"}"""))
        )
    }

    @Test
    fun `no invite for this number`() {
        assertEquals(
            JoinPreviewOutcome.NoInvite("no_matching_invite"),
            JoinPreviews.interpret(decode("""{"matched":false,"reason":"no_matching_invite"}"""))
        )
        assertEquals(
            JoinPreviewOutcome.NoInvite("limit_reached"),
            JoinPreviews.interpret(decode("""{"matched":false,"reason":"limit_reached","message":"full"}"""))
        )
    }

    @Test
    fun `titles fall back when there is no real owner name`() {
        assertEquals("Join The Smiths?", JoinPreviews.title(JoinPreview(ownerName = "User", familyName = "The Smiths")))
        assertEquals("Join this family?", JoinPreviews.title(JoinPreview()))
    }

    @Test
    fun `times format as 12-hour and junk passes through`() {
        assertEquals("12:05 AM", JoinPreviews.formatTime("00:05"))
        assertEquals("1:00 PM", JoinPreviews.formatTime("13:00:00"))
        assertEquals("soon", JoinPreviews.formatTime("soon"))
        assertEquals("25:00", JoinPreviews.formatTime("25:00"))
    }
}
