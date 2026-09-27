package net.dailyok.android.util

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * An invite the owner still has to send. The server records the invite and
 * composes the text (link + setup code) but never sends it — invites go from
 * the owner's own number (see edge-functions invite-receiver). Android used to
 * discard this and tell the owner "a text message has been sent", so nothing
 * was ever sent.
 */
data class InviteToSend(
    val phone: String,
    val message: String,
    val pairingCode: String?
)

object InviteShare {
    /** Open the SMS app to [invite].phone with the text filled in; the share sheet if there is none. */
    fun open(context: Context, invite: InviteToSend) {
        val sms = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${Uri.encode(invite.phone)}")).apply {
            putExtra("sms_body", invite.message)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(sms)
        } catch (_: ActivityNotFoundException) {
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, invite.message)
            }
            context.startActivity(
                Intent.createChooser(share, "Send the invite").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /** The server's text, or a local one if an older server returned none. */
    fun message(name: String, inviteLink: String?, pairingCode: String?, serverMessage: String?): String {
        if (!serverMessage.isNullOrBlank()) return serverMessage
        val link = inviteLink ?: "https://dailyok.net"
        val code = pairingCode?.let { "\n\nOr enter this setup code in the app: $it" } ?: ""
        return "Hi $name! I'd like to check in with you each day using Daily OK — you just tap \"I'm OK\" once a day.\n\n" +
            "1. Get the app: $link\n2. Sign in, then tap this link again to join.$code"
    }
}
