package net.dailyok.android.viewmodels

import net.dailyok.android.data.models.FamilyMember
import net.dailyok.android.data.models.MemberStatus
import net.dailyok.android.data.models.OpenCheckInRequest
import net.dailyok.android.data.models.UserRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CareTeamRulesTest {

    private fun request(
        status: String = "pending",
        createdAt: String = "2026-09-27T09:00:00+00:00",
        step: Int = 0,
        next: String? = "2026-09-27T09:15:00+00:00",
        stoodDownAt: String? = null,
        claimedBy: String? = null,
        claimedByName: String? = null
    ) = OpenCheckInRequest(
        id = "r1", familyId = "f1", receiverId = "u1", status = status, createdAt = createdAt,
        escalationStep = step, nextEscalationAt = next, stoodDownAt = stoodDownAt,
        claimedBy = claimedBy, claimedByName = claimedByName
    )

    @Test
    fun `a request answered by a later check-in is not open`() {
        val r = CareStatus.resolve(request(status = "missed"), latestCheckInAt = "2026-09-27T10:00:00.123+00:00")
        assertNull(r.request)
        assertFalse(r.canStopAlerts)
    }

    @Test
    fun `a missed request after the last check-in is open and claimable`() {
        val r = CareStatus.resolve(request(status = "missed", step = 2), latestCheckInAt = "2026-09-26T09:00:00Z")
        assertTrue(r.isMissed)
        assertTrue(r.canClaim)
        assertTrue(r.canStopAlerts)
    }

    @Test
    fun `a fresh pending request can be stood down but not yet claimed`() {
        val r = CareStatus.resolve(request(), latestCheckInAt = null)
        assertTrue(r.canStopAlerts)
        assertFalse(r.canClaim)
    }

    @Test
    fun `stood down is recorded or inferred, and re-arming undoes it`() {
        assertTrue(CareStatus.resolve(request(stoodDownAt = "2026-09-27T09:20:00Z", next = null), null).stoodDown)
        // pre-00055: stepped, pending, no next step
        assertTrue(CareStatus.resolve(request(step = 1, next = null), null).stoodDown)
        // re-armed after a stand-down (snooze): escalation runs again
        assertFalse(CareStatus.resolve(request(stoodDownAt = "2026-09-27T09:20:00Z", next = "2026-09-27T10:00:00Z"), null).stoodDown)
    }

    @Test
    fun `claim line says who is on it`() {
        assertEquals("You're on it", CareStatus.claimLine(request(claimedBy = "me", claimedByName = "Dj"), "me"))
        assertEquals("Tom is on it", CareStatus.claimLine(request(claimedBy = "t", claimedByName = "Tom"), "me"))
        assertEquals("A caregiver is on it", CareStatus.claimLine(request(claimedBy = "t", claimedByName = " "), "me"))
        assertNull(CareStatus.claimLine(request(), "me"))
    }

    private fun member(role: UserRole, status: MemberStatus) =
        FamilyMember(id = "m", familyId = "f1", userId = "u", role = role, status = status)

    @Test
    fun `only an active co-caregiver can become owner`() {
        assertTrue(FamilySeats.canReceiveOwnership(member(UserRole.Viewer, MemberStatus.Active)))
        assertFalse(FamilySeats.canReceiveOwnership(member(UserRole.Receiver, MemberStatus.Active)))
        assertFalse(FamilySeats.canReceiveOwnership(member(UserRole.Viewer, MemberStatus.Deactivated)))
        assertFalse(FamilySeats.canReceiveOwnership(member(UserRole.Viewer, MemberStatus.Invited)))
    }

    @Test
    fun `co-caregiver seats count active viewers only`() {
        val seats = FamilySeats.viewerSeats(
            listOf(
                member(UserRole.Viewer, MemberStatus.Active),
                member(UserRole.Viewer, MemberStatus.Deactivated),
                member(UserRole.Receiver, MemberStatus.Active),
                member(UserRole.Owner, MemberStatus.Active)
            ),
            maxViewers = 1
        )
        assertEquals(1, seats.used)
        assertTrue(seats.isFull)
        assertTrue(FamilySeats.viewerSeats(emptyList(), 0).isFull)
        assertEquals("No co-caregiver seats on your plan", FamilySeats.seatsLine(FamilySeats.Seats(0, 0)))
    }

    @Test
    fun `help kinds map to the edge function's fields`() {
        assertEquals("need_help", ReceiverHelpKind.NeedHelp.responseType)
        assertNull(ReceiverHelpKind.NeedHelp.kidResponseType)
        assertEquals("ok", ReceiverHelpKind.Sos.responseType)
        assertEquals("sos", ReceiverHelpKind.Sos.kidResponseType)
        assertTrue(ReceiverHelpKind.Sos.isUrgent)
        assertFalse(ReceiverHelpKind.PickMeUp.isUrgent)
        assertEquals(ReceiverHelpKind.StayLonger, ReceiverHelpKind.fromKidResponse("can_stay_longer"))
        assertNull(ReceiverHelpKind.fromKidResponse("nope"))
    }
}
