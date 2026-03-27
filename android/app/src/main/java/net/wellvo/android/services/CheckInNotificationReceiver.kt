package net.wellvo.android.services

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import dagger.hilt.android.AndroidEntryPoint
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject

@AndroidEntryPoint
class CheckInNotificationReceiver : BroadcastReceiver() {

    @Inject
    lateinit var checkInService: CheckInService

    @Inject
    lateinit var supabase: SupabaseClient

    private val receiverScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        private const val TAG = "CheckInReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra(WellvoFirebaseMessagingService.EXTRA_NOTIFICATION_ID, -1)

        // Dismiss the notification
        if (notificationId != -1) {
            NotificationManagerCompat.from(context).cancel(notificationId)
        }

        when (intent.action) {
            WellvoFirebaseMessagingService.ACTION_CHECKIN_OK,
            WellvoFirebaseMessagingService.ACTION_CHECKIN_NEED_HELP,
            WellvoFirebaseMessagingService.ACTION_CHECKIN_CALL_ME -> {
                handleCheckInAction(context, intent)
            }
            WellvoFirebaseMessagingService.ACTION_CALL_NOW -> {
                handleCallNow(context, intent)
            }
            else -> Log.w(TAG, "Unknown action: ${intent.action}")
        }
    }

    private fun handleCheckInAction(context: Context, intent: Intent) {
        val requestId = intent.getStringExtra(WellvoFirebaseMessagingService.EXTRA_REQUEST_ID)
        if (requestId == null) {
            Log.e(TAG, "No request ID in check-in action")
            return
        }

        val source = when (intent.action) {
            WellvoFirebaseMessagingService.ACTION_CHECKIN_OK -> "notification"
            WellvoFirebaseMessagingService.ACTION_CHECKIN_NEED_HELP -> "need_help"
            WellvoFirebaseMessagingService.ACTION_CHECKIN_CALL_ME -> "call_me"
            else -> "notification"
        }

        Log.d(TAG, "Processing check-in response: source=$source, requestId=$requestId")

        val batteryLevel = CheckInService.getBatteryLevel(context)
        val location = getLastKnownLocation(context)

        val pendingResult = goAsync()
        receiverScope.launch {
            try {
                checkInService.respondToCheckIn(
                    requestId = requestId,
                    source = source,
                    latitude = location?.first,
                    longitude = location?.second,
                    locationAccuracy = location?.third,
                    batteryLevel = batteryLevel
                )
                Log.d(TAG, "Check-in response sent successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send check-in response", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun handleCallNow(context: Context, intent: Intent) {
        val receiverId = intent.getStringExtra(WellvoFirebaseMessagingService.EXTRA_RECEIVER_ID)
        if (receiverId == null) {
            Log.e(TAG, "No receiver ID for Call Now action")
            return
        }

        val pendingResult = goAsync()
        receiverScope.launch {
            try {
                val user = supabase.postgrest.from("users")
                    .select {
                        filter { eq("id", receiverId) }
                    }
                    .decodeSingleOrNull<UserPhone>()

                val phone = user?.phone
                if (phone != null) {
                    val callIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(callIntent)
                    Log.d(TAG, "Opened dialer for receiver $receiverId")
                } else {
                    Log.w(TAG, "No phone number found for receiver $receiverId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to look up receiver phone", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    @Suppress("MissingPermission")
    private fun getLastKnownLocation(context: Context): Triple<Double, Double, Double>? {
        val hasPermission = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasPermission) return null

        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null

        val location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            ?: locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            ?: return null

        return Triple(location.latitude, location.longitude, location.accuracy.toDouble())
    }

    @Serializable
    private data class UserPhone(
        val id: String,
        val phone: String? = null,
        @SerialName("display_name")
        val displayName: String? = null
    )
}
