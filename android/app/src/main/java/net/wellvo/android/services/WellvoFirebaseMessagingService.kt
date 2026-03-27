package net.wellvo.android.services

import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import net.wellvo.android.R
import net.wellvo.android.WellvoApplication
import net.wellvo.android.util.SecureStorage
import javax.inject.Inject

@AndroidEntryPoint
class WellvoFirebaseMessagingService : FirebaseMessagingService() {

    @Inject
    lateinit var supabase: SupabaseClient

    @Inject
    lateinit var secureStorage: SecureStorage

    @Inject
    lateinit var checkInService: CheckInService

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        private const val TAG = "WellvoFCM"
        const val ACTION_CHECKIN_OK = "net.wellvo.android.ACTION_CHECKIN_OK"
        const val ACTION_CHECKIN_NEED_HELP = "net.wellvo.android.ACTION_CHECKIN_NEED_HELP"
        const val ACTION_CHECKIN_CALL_ME = "net.wellvo.android.ACTION_CHECKIN_CALL_ME"
        const val ACTION_CALL_NOW = "net.wellvo.android.ACTION_CALL_NOW"
        const val EXTRA_REQUEST_ID = "extra_request_id"
        const val EXTRA_NOTIFICATION_ID = "extra_notification_id"
        const val EXTRA_RECEIVER_ID = "extra_receiver_id"
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "New FCM token received")

        val storedToken = secureStorage.load(SecureStorage.PUSH_TOKEN)
        if (token == storedToken) {
            Log.d(TAG, "Token unchanged, skipping update")
            return
        }

        val userId = secureStorage.load(SecureStorage.USER_ID)
        if (userId == null) {
            Log.w(TAG, "No user ID available, saving token locally for later registration")
            secureStorage.save(SecureStorage.PUSH_TOKEN, token)
            return
        }

        serviceScope.launch {
            try {
                if (storedToken != null) {
                    try {
                        supabase.postgrest.from("push_tokens")
                            .update(mapOf("is_active" to false)) {
                                filter {
                                    eq("user_id", userId)
                                    eq("token", storedToken)
                                }
                            }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to deactivate old token", e)
                    }
                }

                supabase.postgrest.from("push_tokens")
                    .upsert(
                        mapOf(
                            "user_id" to userId,
                            "token" to token,
                            "platform" to "android",
                            "is_active" to true
                        )
                    )

                secureStorage.save(SecureStorage.PUSH_TOKEN, token)
                Log.d(TAG, "FCM token updated in Supabase")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to register new FCM token", e)
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.d(TAG, "Message received: type=${message.data["type"]}")

        val data = message.data
        val type = data["type"] ?: return

        when (type) {
            "CHECKIN_REQUEST" -> handleCheckInRequest(data)
            "URGENT_ALERT" -> handleUrgentAlert(data)
            "LOCATION_ALERT" -> handleLocationAlert(data)
            else -> Log.w(TAG, "Unknown notification type: $type")
        }

        // Confirm delivery
        val requestId = data["request_id"]
        if (requestId != null) {
            serviceScope.launch {
                try {
                    checkInService.confirmDelivery(requestId)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to confirm delivery", e)
                }
            }
        }
    }

    private fun handleCheckInRequest(data: Map<String, String>) {
        val requestId = data["request_id"] ?: return
        val title = data["title"] ?: "Check-in Time"
        val body = data["body"] ?: "Are you OK? Tap to respond."
        val notificationId = requestId.hashCode()

        val okIntent = Intent(this, CheckInNotificationReceiver::class.java).apply {
            action = ACTION_CHECKIN_OK
            putExtra(EXTRA_REQUEST_ID, requestId)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        val okPendingIntent = PendingIntent.getBroadcast(
            this, notificationId, okIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val helpIntent = Intent(this, CheckInNotificationReceiver::class.java).apply {
            action = ACTION_CHECKIN_NEED_HELP
            putExtra(EXTRA_REQUEST_ID, requestId)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        val helpPendingIntent = PendingIntent.getBroadcast(
            this, notificationId + 1, helpIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val callMeIntent = Intent(this, CheckInNotificationReceiver::class.java).apply {
            action = ACTION_CHECKIN_CALL_ME
            putExtra(EXTRA_REQUEST_ID, requestId)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        val callMePendingIntent = PendingIntent.getBroadcast(
            this, notificationId + 2, callMeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentIntent = createContentIntent(
            notificationType = "CHECKIN_REQUEST",
            requestId = requestId,
            receiverId = data["receiver_id"],
            notificationId = notificationId
        )

        val notification = NotificationCompat.Builder(this, WellvoApplication.CHANNEL_CHECKIN_REQUESTS)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .addAction(0, "I'm OK \u2713", okPendingIntent)
            .addAction(0, "I Need Help", helpPendingIntent)
            .addAction(0, "Call Me", callMePendingIntent)
            .build()

        try {
            NotificationManagerCompat.from(this).notify(notificationId, notification)
        } catch (e: SecurityException) {
            Log.e(TAG, "Notification permission not granted", e)
        }
    }

    private fun handleUrgentAlert(data: Map<String, String>) {
        val title = data["title"] ?: "Urgent Alert"
        val body = data["body"] ?: "A family member needs immediate attention."
        val receiverId = data["receiver_id"]
        val notificationId = (data["alert_id"] ?: title).hashCode()

        val contentIntent = createContentIntent(
            notificationType = "URGENT_ALERT",
            requestId = data["alert_id"],
            receiverId = receiverId,
            notificationId = notificationId
        )

        val builder = NotificationCompat.Builder(this, WellvoApplication.CHANNEL_URGENT_ALERTS)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)

        if (receiverId != null) {
            val callIntent = Intent(this, CheckInNotificationReceiver::class.java).apply {
                action = ACTION_CALL_NOW
                putExtra(EXTRA_RECEIVER_ID, receiverId)
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            }
            val callPendingIntent = PendingIntent.getBroadcast(
                this, notificationId + 3, callIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, "Call Now", callPendingIntent)
        }

        try {
            NotificationManagerCompat.from(this).notify(notificationId, builder.build())
        } catch (e: SecurityException) {
            Log.e(TAG, "Notification permission not granted", e)
        }
    }

    private fun handleLocationAlert(data: Map<String, String>) {
        val title = data["title"] ?: "Location Alert"
        val body = data["body"] ?: "A family member's location has changed."
        val notificationId = (data["alert_id"] ?: title).hashCode()

        val contentIntent = createContentIntent(
            notificationType = "LOCATION_ALERT",
            requestId = data["alert_id"],
            receiverId = data["receiver_id"],
            notificationId = notificationId
        )

        val builder = NotificationCompat.Builder(this, WellvoApplication.CHANNEL_LOCATION_ALERTS)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .addAction(0, "View Details", contentIntent)

        try {
            NotificationManagerCompat.from(this).notify(notificationId, builder.build())
        } catch (e: SecurityException) {
            Log.e(TAG, "Notification permission not granted", e)
        }
    }

    private fun createContentIntent(
        notificationType: String,
        requestId: String?,
        receiverId: String?,
        notificationId: Int
    ): PendingIntent {
        val intent = Intent(this, net.wellvo.android.MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("notification_type", notificationType)
            requestId?.let { putExtra("request_id", it) }
            receiverId?.let { putExtra("receiver_id", it) }
        }
        return PendingIntent.getActivity(
            this, notificationId + 100, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
