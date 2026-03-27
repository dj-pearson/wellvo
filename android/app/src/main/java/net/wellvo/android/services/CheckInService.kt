package net.wellvo.android.services

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import net.wellvo.android.data.models.CheckIn
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.CheckInResponseRequest
import net.wellvo.android.network.ConfirmDeliveryRequest
import net.wellvo.android.network.OnDemandCheckinRequest
import net.wellvo.android.network.WellvoError
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CheckInService @Inject constructor(
    private val supabase: SupabaseClient,
    private val apiService: ApiService
) {
    suspend fun checkIn(
        familyId: String,
        receiverId: String,
        requestId: String,
        mood: String? = null,
        source: String = "app",
        latitude: Double? = null,
        longitude: Double? = null,
        locationAccuracy: Double? = null,
        kidResponseType: String? = null
    ): String {
        try {
            return apiService.processCheckinResponse(
                CheckInResponseRequest(
                    requestId = requestId,
                    mood = mood,
                    source = source,
                    latitude = latitude,
                    longitude = longitude,
                    locationAccuracyMeters = locationAccuracy,
                    kidResponseType = kidResponseType
                )
            )
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Check-in failed.")
        }
    }

    suspend fun respondToCheckIn(
        requestId: String,
        source: String = "notification",
        responseType: String? = null,
        latitude: Double? = null,
        longitude: Double? = null,
        locationAccuracy: Double? = null,
        batteryLevel: Double? = null
    ): String {
        try {
            return apiService.processCheckinResponse(
                CheckInResponseRequest(
                    requestId = requestId,
                    source = source,
                    latitude = latitude,
                    longitude = longitude,
                    locationAccuracyMeters = locationAccuracy
                )
            )
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to respond to check-in.")
        }
    }

    suspend fun confirmDelivery(checkinRequestId: String) {
        try {
            apiService.confirmDelivery(ConfirmDeliveryRequest(requestId = checkinRequestId))
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to confirm delivery.")
        }
    }

    suspend fun sendOnDemandCheckIn(familyId: String, receiverId: String): String {
        try {
            return apiService.onDemandCheckin(
                OnDemandCheckinRequest(receiverId = receiverId, familyId = familyId)
            )
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to send on-demand check-in.")
        }
    }

    suspend fun todayCheckInStatus(receiverId: String, familyId: String): CheckIn? {
        try {
            val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
            return supabase.postgrest.from("checkins")
                .select {
                    filter { eq("receiver_id", receiverId) }
                    filter { eq("family_id", familyId) }
                    filter { gte("checked_in_at", "${today}T00:00:00") }
                    filter { lt("checked_in_at", "${today}T23:59:59.999") }
                }
                .decodeSingleOrNull<CheckIn>()
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to check today's status.")
        }
    }

    suspend fun checkInHistory(receiverId: String, familyId: String, days: Int): List<CheckIn> {
        try {
            val startDate = LocalDate.now().minusDays(days.toLong())
                .format(DateTimeFormatter.ISO_LOCAL_DATE)
            return supabase.postgrest.from("checkins")
                .select {
                    filter { eq("receiver_id", receiverId) }
                    filter { eq("family_id", familyId) }
                    filter { gte("checked_in_at", "${startDate}T00:00:00") }
                }
                .decodeList<CheckIn>()
        } catch (e: Exception) {
            throw WellvoError.Unknown(e.message ?: "Failed to fetch check-in history.")
        }
    }

    suspend fun getTodayPendingRequest(receiverId: String, familyId: String): net.wellvo.android.data.models.CheckInRequest? {
        try {
            val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
            return supabase.postgrest.from("checkin_requests")
                .select {
                    filter { eq("receiver_id", receiverId) }
                    filter { eq("family_id", familyId) }
                    filter { eq("status", "pending") }
                    filter { gte("created_at", "${today}T00:00:00") }
                }
                .decodeSingleOrNull()
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        fun getBatteryLevel(context: Context): Double? {
            val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = context.registerReceiver(null, intentFilter) ?: return null
            val level = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level == -1 || scale == -1) return null
            return level.toDouble() / scale.toDouble() * 100.0
        }
    }
}
