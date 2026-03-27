package net.wellvo.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.RealtimeChannel
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
import net.wellvo.android.data.models.CheckIn
import net.wellvo.android.data.models.Family
import net.wellvo.android.data.models.Mood
import net.wellvo.android.data.models.MemberStatus
import net.wellvo.android.data.models.UserRole
import net.wellvo.android.data.models.WellvoAlert
import net.wellvo.android.data.models.emoji
import net.wellvo.android.services.CheckInService
import net.wellvo.android.services.FamilyService
import net.wellvo.android.network.WellvoError
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import javax.inject.Inject

enum class ReceiverCheckInStatus(val label: String) {
    CheckedIn("Checked In"),
    Pending("Pending"),
    Missed("Missed"),
    NoData("No Data");
}

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
    private val familyService: FamilyService
) : ViewModel() {

    private val _family = MutableStateFlow<Family?>(null)
    val family: StateFlow<Family?> = _family.asStateFlow()

    private val _receiverCards = MutableStateFlow<List<ReceiverStatusCard>>(emptyList())
    val receiverCards: StateFlow<List<ReceiverStatusCard>> = _receiverCards.asStateFlow()

    private val _weeklySummary = MutableStateFlow<WeeklySummary?>(null)
    val weeklySummary: StateFlow<WeeklySummary?> = _weeklySummary.asStateFlow()

    private val _alerts = MutableStateFlow<List<WellvoAlert>>(emptyList())
    val alerts: StateFlow<List<WellvoAlert>> = _alerts.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private var currentUserId: String? = null

    fun loadDashboard(userId: String) {
        currentUserId = userId
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null

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

                val cards = mutableListOf<ReceiverStatusCard>()
                val weeklyCheckIns = mutableListOf<CheckIn>()
                val sevenDaysAgo = LocalDate.now().minusDays(7)
                    .format(DateTimeFormatter.ISO_LOCAL_DATE)

                for (receiver in receivers) {
                    val todayCheckIn = try {
                        checkInService.todayCheckInStatus(
                            receiverId = receiver.userId,
                            familyId = fetchedFamily.id
                        )
                    } catch (_: Exception) { null }

                    val history = try {
                        checkInService.checkInHistory(
                            receiverId = receiver.userId,
                            familyId = fetchedFamily.id,
                            days = 30
                        )
                    } catch (_: Exception) { emptyList() }

                    val streak = calculateStreak(history)
                    val hasNotifications = checkNotificationStatus(receiver.userId)

                    // Collect last 7 days for weekly summary
                    weeklyCheckIns.addAll(history.filter {
                        it.checkedInAt >= "${sevenDaysAgo}T00:00:00"
                    })

                    cards.add(
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
                            hasNotificationsEnabled = hasNotifications,
                            checkedInTime = todayCheckIn?.checkedInAt,
                            locationLabel = todayCheckIn?.locationLabel,
                            kidResponseType = todayCheckIn?.kidResponseType
                        )
                    )
                }

                _receiverCards.value = cards
                _weeklySummary.value = computeWeeklySummary(weeklyCheckIns, receivers.size)
                loadAlerts(fetchedFamily.id)
            } catch (e: WellvoError) {
                _errorMessage.value = e.localizedMessage
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load dashboard."
            }

            _isLoading.value = false
        }
    }

    fun sendOnDemandCheckIn(receiverId: String) {
        val familyId = _family.value?.id ?: return
        viewModelScope.launch {
            try {
                checkInService.sendOnDemandCheckIn(familyId = familyId, receiverId = receiverId)
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to send check-in request."
            }
        }
    }

    fun dismissAlert(alert: WellvoAlert) {
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

    private suspend fun loadAlerts(familyId: String) {
        try {
            _alerts.value = supabase.postgrest.from("alerts")
                .select {
                    filter { eq("family_id", familyId) }
                    filter { eq("is_read", false) }
                }
                .decodeList<WellvoAlert>()
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

    private suspend fun checkNotificationStatus(userId: String): Boolean {
        return try {
            val tokens = supabase.postgrest.from("push_tokens")
                .select {
                    filter { eq("user_id", userId) }
                    filter { eq("is_active", true) }
                }
                .decodeList<PushTokenRecord>()
            tokens.isNotEmpty()
        } catch (_: Exception) {
            false
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
