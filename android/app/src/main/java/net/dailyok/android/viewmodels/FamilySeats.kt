package net.dailyok.android.viewmodels

import net.dailyok.android.data.models.FamilyMember
import net.dailyok.android.data.models.MemberStatus
import net.dailyok.android.data.models.UserRole

/**
 * Family-tab rules with no I/O, so they are unit-testable. The server
 * enforces the same limits (invite-receiver counts co-caregiver seats,
 * transfer_family_ownership_v2 refuses a receiver); these keep the app from
 * offering what the server would refuse.
 */
object FamilySeats {
    data class Seats(val used: Int, val max: Int) {
        val isFull: Boolean get() = used >= max
        val remaining: Int get() = (max - used).coerceAtLeast(0)
    }

    /** Active co-caregivers against the plan's families.max_viewers. */
    fun viewerSeats(members: List<FamilyMember>, maxViewers: Int): Seats = Seats(
        used = members.count { it.role == UserRole.Viewer && it.status == MemberStatus.Active },
        max = maxViewers.coerceAtLeast(0)
    )

    /**
     * Only an active co-caregiver can take over the family. A receiver is the
     * person being checked on: as owner their own missed check-ins would page
     * them. An invited or removed member isn't in the family.
     */
    fun canReceiveOwnership(member: FamilyMember): Boolean =
        member.role == UserRole.Viewer && member.status == MemberStatus.Active

    fun fullMessage(seats: Seats): String = if (seats.max == 0) {
        "Your plan doesn't include co-caregivers. Upgrade to add one."
    } else {
        "All ${seats.max} co-caregiver seats on your plan are taken. Upgrade, or remove a co-caregiver first."
    }

    /** "2 of 3 co-caregiver seats used" */
    fun seatsLine(seats: Seats): String =
        if (seats.max == 0) "No co-caregiver seats on your plan"
        else "${seats.used} of ${seats.max} co-caregiver seats used"
}
