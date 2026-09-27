package net.dailyok.android.services

import android.app.PendingIntent
import android.content.Intent
import net.dailyok.android.util.DebugLog as Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import net.dailyok.android.R
import net.dailyok.android.DailyOKApplication
import net.dailyok.android.util.SecureStorage
import javax.inject.Inject

@AndroidEntryPoint
class DailyOKFirebaseMessagingService : FirebaseMessagingService() {

    @Inject
    lateinit var secureStorage: SecureStorage

    @Inject
    lateinit var checkInService: CheckInService

    @Inject
    lateinit var pushNotificationService: PushNotificationService

    private val supervisorJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + supervisorJob)

    companion object {
        private const val TAG = "DailyOKFCM"
        const val ACTION_CHECKIN_OK = "net.dailyok.android.ACTION_CHECKIN_OK"
        const val ACTION_CHECKIN_NEED_HELP = "net.dailyok.android.ACTION_CHECKIN_NEED_HELP"
        const val ACTION_CHECKIN_CALL_ME = "net.dailyok.android.ACTION_CHECKIN_CALL_ME"
        const val ACTION_CALL_NOW = "net.dailyok.android.ACTION_CALL_NOW"
        const val EXTRA_REQUEST_ID = "extra_request_id"
        const val EXTRA_NOTIFICATION_ID = "extra_notification_id"
        const val EXTRA_RECEIVER_ID = "extra_receiver_id"
    }

    override fun onDestroy() {
        super.onDestroy()
        supervisorJob.cancel()
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "New FCM token received")

        val userId = secureStorage.load(SecureStorage.USER_ID)
        if (userId == null) {
            Log.w(TAG, "No user ID available, saving token locally for later registration")
            secureStorage.saveSync(SecureStorage.PUSH_TOKEN, token)
            return
        }

        serviceScope.launch {
            try {
                pushNotificationService.upsertToken(userId, token)
                Log.d(TAG, "FCM token updated via PushNotificationService")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to register new FCM token", e)
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        if (net.dailyok.android.BuildConfig.DEBUG) {
            Log.d(TAG, "Message received: type=${message.data["type"]}")
        }

        val data = message.data
        val type = data["type"] ?: return

        // The server's `type` values (edge-functions): check-in prompts are
        // CHECKIN_REQUEST; owner-facing alerts use lowercase names. Only the
        // three uppercase names used to be handled, so a missed check-in
        // (owner_alert) never showed on Android.
        when (type) {
            "CHECKIN_REQUEST" -> handleCheckInRequest(data)
            "URGENT_ALERT", "urgent_alert", "owner_alert", "kid_response" -> handleUrgentAlert(data)
            "LOCATION_ALERT", "geofence_alert", "low_battery_alert", "viewer_alert" -> handleLocationAlert(data)
            else -> handleFamilyUpdate(data, type)
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

        val notification = NotificationCompat.Builder(this, DailyOKApplication.CHANNEL_CHECKIN_REQUESTS)
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

        val builder = NotificationCompat.Builder(this, DailyOKApplication.CHANNEL_URGENT_ALERTS)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)

        if (receiverId != null) {
            // Opens the app, which looks up the number and opens the dialer.
            // A BroadcastReceiver starting the dialer (the old route) is a
            // notification trampoline, which Android 12+ blocks — so the
            // button did nothing on most phones.
            val callIntent = Intent(this, net.dailyok.android.MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(net.dailyok.android.MainActivity.EXTRA_CALL_RECEIVER_ID, receiverId)
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            }
            val callPendingIntent = PendingIntent.getActivity(
                this, notificationId + 3, callIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, "Call Now", callPendingIntent)
            builder.addAction(0, "Text", textReceiverPendingIntent(receiverId, data["type"], notificationId))
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

        val builder = NotificationCompat.Builder(this, DailyOKApplication.CHANNEL_LOCATION_ALERTS)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .addAction(0, "View Details", contentIntent)

        // The co-caregivers' page (viewer_alert) is the last step of a missed
        // check-in: offer a pre-filled text to the receiver from this phone.
        val receiverId = data["receiver_id"]
        if (data["type"] == "viewer_alert" && receiverId != null) {
            builder.addAction(0, "Text", textReceiverPendingIntent(receiverId, data["type"], notificationId))
        }

        try {
            NotificationManagerCompat.from(this).notify(notificationId, builder.build())
        } catch (e: SecurityException) {
            Log.e(TAG, "Notification permission not granted", e)
        }
    }

    private fun handleFamilyUpdate(data: Map<String, String>, type: String) {
        val title = data["title"] ?: return
        val body = data["body"] ?: ""
        val notificationId = (data["checkin_request_id"] ?: data["checkin_id"] ?: "$type:$title:$body").hashCode()

        val contentIntent = createContentIntent(
            notificationType = type,
            requestId = data["checkin_request_id"],
            receiverId = data["receiver_id"],
            notificationId = notificationId
        )

        val notification = NotificationCompat.Builder(this, DailyOKApplication.CHANNEL_FAMILY_UPDATES)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        try {
            NotificationManagerCompat.from(this).notify(notificationId, notification)
        } catch (e: SecurityException) {
            Log.e(TAG, "Notification permission not granted", e)
        }
    }

    /**
     * "Text": opens the app, which looks up the receiver's number and opens the
     * SMS app with a short note filled in. Daily OK sends no texts itself.
     * (An activity, not a BroadcastReceiver: Android 12+ blocks trampolines.)
     */
    private fun textReceiverPendingIntent(receiverId: String, alertType: String?, notificationId: Int): PendingIntent {
        val intent = Intent(this, net.dailyok.android.MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(net.dailyok.android.MainActivity.EXTRA_TEXT_RECEIVER_ID, receiverId)
            alertType?.let { putExtra(net.dailyok.android.MainActivity.EXTRA_TEXT_ALERT_TYPE, it) }
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        return PendingIntent.getActivity(
            this, notificationId + 4, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createContentIntent(
        notificationType: String,
        requestId: String?,
        receiverId: String?,
        notificationId: Int
    ): PendingIntent {
        val intent = Intent(this, net.dailyok.android.MainActivity::class.java).apply {
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
