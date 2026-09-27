package net.dailyok.android.viewmodels

import net.dailyok.android.data.models.OpenCheckInRequest
import java.time.Instant
import java.time.OffsetDateTime

/**
 * Where a receiver's open check-in request stands for the caregivers. Pure,
 * so it is unit-testable; same rules as iOS DashboardViewModel.resolveStatus.
 */
object CareStatus {
    data class Resolution(
        /** The request nobody has answered yet, if any. */
        val request: OpenCheckInRequest?,
        /** Escalation was stopped by a caregiver ("Stop alerts"). */
        val stoodDown: Boolean
    ) {
        val isMissed: Boolean get() = request?.isMissed == true
        /** Alerts are still going out for this request: "Stop alerts" makes sense. */
        val canStopAlerts: Boolean get() = request != null && !stoodDown
        /** "I'm on it" only for a request that is overdue or missed. */
        val canClaim: Boolean get() = request != null &&
            (request.isMissed || request.escalationStep >= 1)
    }

    /**
     * [latestCheckInAt] is the newest check-in on any day. A request created
     * before it has been answered (a missed row is never closed server-side,
     * so without this one miss last week would show every morning).
     */
    fun resolve(activeRequest: OpenCheckInRequest?, latestCheckInAt: String?): Resolution {
        val answeredAt = latestCheckInAt?.let(::parseInstant)
        val createdAt = activeRequest?.createdAt?.let(::parseInstant)
        val unanswered = if (activeRequest != null && !(answeredAt != null && createdAt != null && !answeredAt.isBefore(createdAt))) {
            activeRequest
        } else {
            null
        }
        // Stood down: recorded by the server (00055), or — before that column
        // — a request that had started escalating and has no next step
        // (only cancel-escalation leaves it that way). A pending request with
        // a stand-down record but a live escalation clock was re-armed since.
        val stoodDown = unanswered != null && (
            (unanswered.stoodDownAt != null && (unanswered.isMissed || unanswered.nextEscalationAt == null)) ||
                (unanswered.isPending && unanswered.escalationStep >= 1 && unanswered.nextEscalationAt == null)
            )
        return Resolution(request = unanswered, stoodDown = stoodDown)
    }

    /** "You're on it" / "Tom is on it", or null when nobody is. */
    fun claimLine(request: OpenCheckInRequest?, currentUserId: String?): String? {
        val holder = request?.claimedBy ?: return null
        return if (holder == currentUserId) "You're on it" else "${request.claimedByName?.takeIf { it.isNotBlank() } ?: "A caregiver"} is on it"
    }

    fun parseInstant(raw: String): Instant? = try {
        OffsetDateTime.parse(raw).toInstant()
    } catch (_: Exception) {
        try {
            Instant.parse(raw.trimEnd('Z') + "Z")
        } catch (_: Exception) {
            null
        }
    }
}
