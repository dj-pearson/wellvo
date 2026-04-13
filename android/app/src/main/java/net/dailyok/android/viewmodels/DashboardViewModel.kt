package net.dailyok.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.RealtimeChannel
import io.github.jan.supabase.realtime.realtime
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import net.dailyok.android.data.models.CheckIn
import net.dailyok.android.data.models.Family
import net.dailyok.android.data.models.Mood
import net.dailyok.android.data.models.MemberStatus
import net.dailyok.android.data.models.UserRole
import net.dailyok.android.data.models.DailyOKAlert
import net.dailyok.android.data.models.emoji
import net.dailyok.android.services.AnalyticsService
import net.dailyok.android.services.CheckInService
import net.dailyok.android.services.FamilyService
import net.dailyok.android.network.DailyOKError
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import androidx.compose.runtime.Immutable
import javax.inject.Inject

enum class ReceiverCheckInStatus(val label: String) {
    CheckedIn("Checked In"),
    Pending("Pending"),
    Missed("Missed"),
    NoData("No Data");
}

@Immutable
data class ReceiverStatusCard(
    val id: String,
    val memberId: String,
    val name: String,
    val avatarUrl: String?,
    val status: ReceiverCheckInStatus,
    val lastCheckIn: String?,
    val streak: Int,
    val mood: Mood?,
    val hasNotificationsEnabled: Boolean,
    val checkedInTime: String?,
    val locationLabel: String?,
    val kidResponseType: String?
)

@Immutable
data class WeeklySummary(
    val consistencyPercentage: Double,
    val averageCheckInTime: String,
    val totalCheckIns: Int,
    val totalExpected: Int,
    val moodBreakdown: Map<Mood, Int>
)

@Serializable
private data class PushTokenRecord(
    val id: String
)

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val checkInService: CheckInService,
    private val familyService: FamilyService,
    private val analyticsService: AnalyticsService
) : ViewModel() {

    private val _family = MutableStateFlow<Family?>(null)
    val family: StateFlow<Family?> = _family.asStateFlow()

    private val _receiverCards = MutableStateFlow<List<ReceiverStatusCard>>(emptyList())
    val receiverCards: StateFlow<List<ReceiverStatusCard>> = _receiverCards.asStateFlow()

    private val _weeklySummary = MutableStateFlow<WeeklySummary?>(null)
    val weeklySummary: StateFlow<WeeklySummary?> = _weeklySummary.asStateFlow()

    private val _alerts = MutableStateFlow<List<DailyOKAlert>>(emptyList())
    val alerts: StateFlow<List<DailyOKAlert>> = _alerts.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _successMessage = MutableStateFlow<String?>(null)
    val successMessage: StateFlow<String?> = _successMessage.asStateFlow()

    private val _sendingCheckInFor = MutableStateFlow<Set<String>>(emptySet())
    val sendingCheckInFor: StateFlow<Set<String>> = _sendingCheckInFor.asStateFlow()

    private val _cooldownUntil = MutableStateFlow<Map<String, Long>>(emptyMap())
    val cooldownUntil: StateFlow<Map<String, Long>> = _cooldownUntil.asStateFlow()

    private var currentUserId: String? = null
    private var realtimeChannel: RealtimeChannel? = null
    private var realtimeJob: Job? = null
    private var subscribedFamilyId: String? = null

    fun loadDashboard(userId: String) {
        currentUserId = userId
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            analyticsService.track(AnalyticsService.DASHBOARD_VIEWED)

            try {
                val fetchedFamily = familyService.getFamily(userId) ?: run {
                    _isLoading.value = false
                    return@launch
                }
                _family.value = fetchedFamily

                val members = familyService.getFamilyMembers(fetchedFamily.id)
                val receivers = members.filter {
                    it.role == UserRole.Receiver && it.status == MemberStatus.Active
                }

                // Batch queries: 3 queries total instead of 3 per receiver
                val todayCheckIns = try {
                    checkInService.todayCheckInsForFamily(fetchedFamily.id)
                } catch (_: Exception) { emptyList() }

                val allHistory = try {
                    checkInService.familyCheckInHistory(fetchedFamily.id, 30)
                } catch (_: Exception) { emptyList() }

                val allTokens = try {
                    checkNotificationStatusBatch(receivers.map { it.userId })
                } catch (_: Exception) { emptySet() }

                // Group results by receiver for in-memory mapping
                val todayByReceiver = todayCheckIns.groupBy { it.receiverId }
                val historyByReceiver = allHistory.groupBy { it.receiverId }
                val sevenDaysAgo = LocalDate.now().minusDays(7)
                    .format(DateTimeFormatter.ISO_LOCAL_DATE)

                val cards = receivers.map { receiver ->
                    val todayCheckIn = todayByReceiver[receiver.userId]?.firstOrNull()
                    val history = historyByReceiver[receiver.userId] ?: emptyList()
                    val streak = calculateStreak(history)

                    ReceiverStatusCard(
                        id = receiver.userId,
                        memberId = receiver.id,
                        name = receiver.user?.displayName ?: "Unknown",
                        avatarUrl = receiver.user?.avatarUrl,
                        status = if (todayCheckIn != null) ReceiverCheckInStatus.CheckedIn
                                 else ReceiverCheckInStatus.Pending,
                        lastCheckIn = todayCheckIn?.checkedInAt ?: history.firstOrNull()?.checkedInAt,
                        streak = streak,
                        mood = todayCheckIn?.mood,
                        hasNotificationsEnabled = receiver.userId in allTokens,
                        checkedInTime = todayCheckIn?.checkedInAt,
                        locationLabel = todayCheckIn?.locationLabel,
                        kidResponseType = todayCheckIn?.kidResponseType
                    )
                }

                val weeklyCheckIns = allHistory.filter {
                    it.checkedInAt >= "${sevenDaysAgo}T00:00:00"
                }

                _receiverCards.value = cards
                _weeklySummary.value = computeWeeklySummary(weeklyCheckIns, receivers.size)
                loadAlerts(fetchedFamily.id)
                subscribeToRealtime(fetchedFamily.id)
            } catch (e: DailyOKError) {
                _errorMessage.value = e.localizedMessage
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load dashboard."
            }

            _isLoading.value = false
        }
    }

    fun sendOnDemandCheckIn(receiverId: String) {
        val familyId = _family.value?.id ?: return
        val receiverName = _receiverCards.value.find { it.id == receiverId }?.name ?: "receiver"
        viewModelScope.launch {
            _sendingCheckInFor.value = _sendingCheckInFor.value + receiverId
            try {
                checkInService.sendOnDemandCheckIn(familyId = familyId, receiverId = receiverId)
                analyticsService.track(AnalyticsService.ON_DEMAND_SENT)
                _successMessage.value = "Check-in request sent to $receiverName"
                _cooldownUntil.value = _cooldownUntil.value + (receiverId to (System.currentTimeMillis() + 60_000))
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to send check-in request."
            } finally {
                _sendingCheckInFor.value = _sendingCheckInFor.value - receiverId
            }
        }
    }

    fun clearSuccessMessage() {
        _successMessage.value = null
    }

    fun dismissAlert(alert: DailyOKAlert) {
        viewModelScope.launch {
            try {
                supabase.postgrest.from("alerts")
                    .update(buildJsonObject {
                        put("is_read", true)
                    }) {
                        filter { eq("id", alert.id) }
                    }
                _alerts.value = _alerts.value.filter { it.id != alert.id }
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to dismiss alert."
            }
        }
    }

    fun clearError() {
        _errorMessage.value = null
    }

    private suspend fun subscribeToRealtime(familyId: String) {
        // Don't re-subscribe if already listening to the same family
        if (subscribedFamilyId == familyId && realtimeChannel != null) return

        // Unsubscribe from any existing channel
        realtimeJob?.cancel()
        realtimeChannel?.let {
            try { supabase.realtime.removeChannel(it) } catch (_: Exception) {}
        }

        try {
            val channel = supabase.channel("checkins:$familyId")

            val changeFlow = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                table = "checkins"
                filter = "family_id=eq.$familyId"
            }

            realtimeJob = changeFlow.onEach {
                // On any change (INSERT, UPDATE, DELETE), reload the dashboard
                currentUserId?.let { userId -> loadDashboard(userId) }
            }.launchIn(viewModelScope)

            channel.subscribe()
            realtimeChannel = channel
            subscribedFamilyId = familyId
        } catch (_: Exception) {
            // Realtime is non-critical; pull-to-refresh is the fallback
        }
    }

    override fun onCleared() {
        super.onCleared()
        realtimeJob?.cancel()
        realtimeJob = null
        subscribedFamilyId = null
        // Channel cleanup happens automatically when viewModelScope is cancelled
        realtimeChannel = null
    }

    private suspend fun loadAlerts(familyId: String) {
        try {
            _alerts.value = supabase.postgrest.from("alerts")
                .select {
                    filter { eq("family_id", familyId) }
                    filter { eq("is_read", false) }
                }
                .decodeList<DailyOKAlert>()
                .sortedByDescending { it.createdAt }
                .take(10)
        } catch (_: Exception) {
            _alerts.value = emptyList()
        }
    }

    private fun calculateStreak(checkIns: List<CheckIn>): Int {
        if (checkIns.isEmpty()) return 0

        val checkInDays = checkIns.mapNotNull { checkIn ->
            try {
                LocalDate.parse(checkIn.checkedInAt.substring(0, 10))
            } catch (_: DateTimeParseException) { null }
        }.toSet()

        var streak = 0
        var currentDate = LocalDate.now()

        while (checkInDays.contains(currentDate)) {
            streak++
            currentDate = currentDate.minusDays(1)
        }

        return streak
    }

    @Serializable
    private data class PushTokenWithUser(
        val id: String,
        @SerialName("user_id") val userId: String
    )

    private suspend fun checkNotificationStatusBatch(userIds: List<String>): Set<String> {
        if (userIds.isEmpty()) return emptySet()
        return try {
            val tokens = supabase.postgrest.from("push_tokens")
                .select {
                    filter { isIn("user_id", userIds) }
                    filter { eq("is_active", true) }
                }
                .decodeList<PushTokenWithUser>()
            tokens.map { it.userId }.toSet()
        } catch (_: Exception) {
            emptySet()
        }
    }

    private fun computeWeeklySummary(checkIns: List<CheckIn>, receiverCount: Int): WeeklySummary {
        val totalExpected = receiverCount * 7
        val totalCheckIns = checkIns.size
        val consistency = if (totalExpected > 0) {
            (totalCheckIns.toDouble() / totalExpected.toDouble()) * 100
        } else 0.0

        val avgTime = if (checkIns.isNotEmpty()) {
            val totalMinutes = checkIns.sumOf { checkIn ->
                try {
                    val time = parseCheckedInTime(checkIn.checkedInAt)
                    time.hour * 60 + time.minute
                } catch (_: Exception) { 0 }
            }
            val avgMinutes = totalMinutes / checkIns.size
            val hour = avgMinutes / 60
            val minute = avgMinutes % 60
            val time = LocalTime.of(hour.coerceIn(0, 23), minute.coerceIn(0, 59))
            time.format(DateTimeFormatter.ofPattern("h:mm a"))
        } else "--"

        val moodBreakdown = mutableMapOf<Mood, Int>()
        for (checkIn in checkIns) {
            val mood = checkIn.mood ?: continue
            moodBreakdown[mood] = (moodBreakdown[mood] ?: 0) + 1
        }

        return WeeklySummary(
            consistencyPercentage = consistency,
            averageCheckInTime = avgTime,
            totalCheckIns = totalCheckIns,
            totalExpected = totalExpected,
            moodBreakdown = moodBreakdown
        )
    }

    private fun parseCheckedInTime(timestamp: String): LocalTime {
        return try {
            LocalDateTime.parse(timestamp, DateTimeFormatter.ISO_LOCAL_DATE_TIME).toLocalTime()
        } catch (_: DateTimeParseException) {
            try {
                LocalDateTime.parse(timestamp.replace("Z", ""), DateTimeFormatter.ISO_LOCAL_DATE_TIME).toLocalTime()
            } catch (_: DateTimeParseException) {
                LocalTime.MIDNIGHT
            }
        }
    }
}
