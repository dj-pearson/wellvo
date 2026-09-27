package net.dailyok.android.network

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * What a join would do, asked before joining (optional `preview: true` on
 * invite-receiver accept, redeem-code and auto-join; edge pass 6,
 * shared/join-family.ts describeInvite).
 *
 * The same shape also decodes the ordinary join answers, because a server
 * that predates `preview` ignores the flag and joins at once. [interpret]
 * tells the two apart, so an older server still ends in a working join
 * instead of a consent screen for a family the user already joined.
 */
@Serializable
data class JoinPreview(
    /** true only from a server that honoured `preview`. */
    val preview: Boolean? = null,
    /** auto-join only. */
    val matched: Boolean? = null,
    /** accept / redeem-code join answers. */
    val success: Boolean? = null,
    @SerialName("family_id")
    val familyId: String? = null,
    @SerialName("family_name")
    val familyName: String? = null,
    /** "receiver" or "viewer" (co-caregiver); the role they would get or already hold. */
    val role: String? = null,
    @SerialName("owner_name")
    val ownerName: String? = null,
    /** The name the owner typed on the invite. */
    @SerialName("invite_name")
    val inviteName: String? = null,
    @SerialName("checkin_time")
    val checkinTime: String? = null,
    /** Owner and co-caregivers who will see this person's check-ins. */
    val watchers: List<String> = emptyList(),
    @SerialName("already_member")
    val alreadyMember: Boolean? = null,
    /** auto-join "no match" reason. */
    val reason: String? = null
) {
    val isViewer: Boolean get() = role == "viewer"

    /** The owner's name if it is a real one (not blank, not the "User" placeholder). */
    val presentableOwner: String? get() = presentableName(ownerName)

    companion object {
        fun presentableName(raw: String?): String? {
            val trimmed = raw?.trim().orEmpty()
            return if (trimmed.isEmpty() || trimmed == "User") null else trimmed
        }
    }
}

/** What a preview request actually came back as. */
sealed interface JoinPreviewOutcome {
    /** Ask first: nothing has been joined yet. */
    data class AskFirst(val preview: JoinPreview) : JoinPreviewOutcome

    /**
     * Already in the family (the preview said so), or a server that ignored
     * `preview` and joined. Either way: route by [role], no consent screen.
     */
    data class AlreadyJoined(val familyId: String?, val role: String?) : JoinPreviewOutcome

    /** Nothing to join (auto-join found no invite for this number). */
    data class NoInvite(val reason: String?) : JoinPreviewOutcome
}

object JoinPreviews {
    fun interpret(response: JoinPreview): JoinPreviewOutcome {
        if (response.preview == true) {
            if (response.matched == false) return JoinPreviewOutcome.NoInvite(response.reason)
            return if (response.alreadyMember == true) {
                JoinPreviewOutcome.AlreadyJoined(response.familyId, response.role)
            } else {
                JoinPreviewOutcome.AskFirst(response)
            }
        }
        // No `preview` echo: an older server, which joined as it always did.
        if (response.success == true || (response.matched == true && response.familyId != null)) {
            return JoinPreviewOutcome.AlreadyJoined(response.familyId, response.role)
        }
        return JoinPreviewOutcome.NoInvite(response.reason)
    }

    /** "Join Sarah's family?" / "Join The Smiths?" / "Join this family?" */
    fun title(preview: JoinPreview): String {
        val owner = preview.presentableOwner
        val family = JoinPreview.presentableName(preview.familyName)
        return when {
            owner != null -> "Join $owner's family?"
            family != null -> "Join $family?"
            else -> "Join this family?"
        }
    }

    /** One sentence on what joining means for this role. */
    fun explanation(preview: JoinPreview): String {
        val owner = preview.presentableOwner ?: "The family owner"
        return if (preview.isViewer) {
            "You'll be a co-caregiver: you'll see check-ins and be told if one is missed or someone asks for help. You won't be asked to check in yourself."
        } else {
            val time = preview.checkinTime?.let { formatTime(it) }
            if (time != null) {
                "$owner will ask you to tap \"I'm OK\" each day around $time. If you don't, they'll be told."
            } else {
                "$owner will ask you to tap \"I'm OK\" each day. If you don't, they'll be told."
            }
        }
    }

    /** Who will see this person's check-ins, or null when the server named nobody. */
    fun watchersLine(preview: JoinPreview): String? {
        val names = preview.watchers.mapNotNull { JoinPreview.presentableName(it) }.distinct()
        if (names.isEmpty()) return null
        val list = when (names.size) {
            1 -> names[0]
            2 -> "${names[0]} and ${names[1]}"
            else -> names.dropLast(1).joinToString(", ") + " and " + names.last()
        }
        return if (preview.isViewer) "Caring together with $list." else "$list will see your check-ins."
    }

    /** "08:30" or "08:30:00" → "8:30 AM"; anything else is returned as is. */
    fun formatTime(time: String): String {
        val parts = time.split(":")
        if (parts.size < 2) return time
        val hour = parts[0].toIntOrNull() ?: return time
        val minute = parts[1].toIntOrNull() ?: return time
        if (hour !in 0..23 || minute !in 0..59) return time
        val amPm = if (hour < 12) "AM" else "PM"
        val displayHour = when {
            hour == 0 -> 12
            hour > 12 -> hour - 12
            else -> hour
        }
        return "%d:%02d %s".format(displayHour, minute, amPm)
    }
}
