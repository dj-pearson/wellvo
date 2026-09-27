package net.dailyok.android.util

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.util.Locale

/**
 * "Text Mom": a short, pre-filled message opened in the phone's own SMS app
 * and sent from the caregiver's own number. Daily OK's servers send no texts
 * (server SMS needs an A2P 10DLC registration); alerts are push notifications.
 *
 * The message builders are pure (no Android types) so they can be unit tested.
 */
object FamilyText {

    /** "Margaret Smith" -> "Margaret". Falls back to the whole (trimmed) name. */
    fun greetingName(name: String): String {
        val trimmed = name.trim()
        return trimmed.split(Regex("\\s+")).firstOrNull()?.takeIf { it.isNotEmpty() } ?: trimmed
    }

    private fun hi(name: String): String =
        greetingName(name).takeIf { it.isNotEmpty() }?.let { "Hi $it" } ?: "Hi"

    /** Caregiver -> receiver while today's check-in is still outstanding. */
    fun checkingOn(name: String, missed: Boolean): String =
        if (missed) {
            "${hi(name)}, I didn't get your Daily OK check-in today and just want to make sure you're OK. Can you text me back?"
        } else {
            "${hi(name)}, just checking in. I haven't seen your Daily OK tap yet. All good?"
        }

    /** Caregiver -> receiver after a help request ("I need help" / "Call me"). */
    fun helpReply(name: String, callMe: Boolean): String =
        if (callMe) {
            "${hi(name)}, I saw you'd like a call. I'll ring you in a minute. Keep your phone close."
        } else {
            "${hi(name)}, I got your help alert and I'm on it. Are you OK? Call or text me back if you can."
        }

    /** The body for an alert's "Text" action, by the push `type`. */
    fun forAlertType(name: String, type: String?): String = when (type) {
        "call_me" -> helpReply(name, callMe = true)
        "need_help", "sos", "URGENT_ALERT", "urgent_alert" -> helpReply(name, callMe = false)
        "kid_response" -> "${hi(name)}, I got your message. Call or text me back."
        else -> checkingOn(name, missed = true) // owner_alert / viewer_alert: missed check-in
    }

    /**
     * Map link rounded to 3 decimals (about 100 m): enough to find someone, no
     * more precise than it needs to be. Null for a missing or 0,0 fix.
     */
    fun approximateMapLink(latitude: Double?, longitude: Double?): String? {
        if (latitude == null || longitude == null) return null
        if (!latitude.isFinite() || !longitude.isFinite()) return null
        if (kotlin.math.abs(latitude) > 90 || kotlin.math.abs(longitude) > 180) return null
        if (latitude == 0.0 && longitude == 0.0) return null
        return String.format(Locale.US, "https://maps.google.com/?q=%.3f,%.3f", latitude, longitude)
    }

    /** Receiver -> owner: "I need help", with a rough map link when known. */
    fun askingForHelp(ownerName: String?, callMe: Boolean, latitude: Double? = null, longitude: Double? = null): String {
        val greeting = ownerName?.let { greetingName(it) }?.takeIf { it.isNotEmpty() }?.let { "Hi $it, " } ?: ""
        val ask = if (callMe) "can you call me as soon as you can?" else "I need help. Please call me as soon as you can."
        var body = greeting + ask
        if (greeting.isEmpty()) body = body.replaceFirstChar { it.uppercase() }
        approximateMapLink(latitude, longitude)?.let { body += "\nI'm around here: $it" }
        return body
    }

    /** Keep only dialable characters; null when nothing is left. */
    fun dialable(phone: String?): String? {
        val cleaned = phone?.filter { it.isDigit() || it == '+' }.orEmpty()
        return cleaned.takeIf { it.count(Char::isDigit) >= 3 }
    }

    /**
     * Open the SMS app to [phone] with [body] filled in (ACTION_SENDTO smsto:),
     * or the share sheet when there's no SMS app. Nothing is sent until the
     * person taps Send.
     */
    fun open(context: Context, phone: String, body: String) {
        val number = dialable(phone) ?: phone
        val sms = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${Uri.encode(number)}")).apply {
            putExtra("sms_body", body)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(sms)
        } catch (_: ActivityNotFoundException) {
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, body)
            }
            context.startActivity(
                Intent.createChooser(share, "Send a message").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }
}
