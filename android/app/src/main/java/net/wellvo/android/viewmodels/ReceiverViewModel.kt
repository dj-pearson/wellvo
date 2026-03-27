package net.wellvo.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.data.models.CheckIn
import net.wellvo.android.data.models.CheckInRequest
import net.wellvo.android.data.models.DaySchedule
import net.wellvo.android.data.models.FamilyMember
import net.wellvo.android.data.models.Mood
import net.wellvo.android.data.models.ReceiverSettings
import net.wellvo.android.data.models.ScheduleType
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale
import net.wellvo.android.network.WellvoError
import net.wellvo.android.services.CheckInService
import net.wellvo.android.services.OfflineCheckInService
import javax.inject.Inject

data class ReceiverUiState(
    val hasCheckedInToday: Boolean = false,
    val isCheckingIn: Boolean = false,
    val lastCheckIn: CheckIn? = null,
    val errorMessage: String? = null,
    val nextCheckInTime: String? = null,
    val receiverName: String = "",
    val pendingRequestId: String? = null,
    val familyId: String? = null,
    val receiverId: String? = null,
    val isLoading: Boolean = true,
    val selectedMood: Mood? = null,
    val showMoodSelector: Boolean = false,
    val isKidMode: Boolean = false,
    val selectedLocationLabel: String? = null,
    val selectedKidResponse: String? = null,
    val showLocationSelector: Boolean = false,
    val showKidResponseButtons: Boolean = false
)

@HiltViewModel
class ReceiverViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val checkInService: CheckInService,
    private val offlineCheckInService: OfflineCheckInService
) : ViewModel() {

    val isOffline: StateFlow<Boolean> = offlineCheckInService.isOffline
    val pendingOfflineCount: StateFlow<Int> = offlineCheckInService.pendingOfflineCount

    private val _uiState = MutableStateFlow(ReceiverUiState())
    val uiState: StateFlow<ReceiverUiState> = _uiState.asStateFlow()

    init {
        loadReceiverState()
    }

    private fun loadReceiverState() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch

                val member = supabase.postgrest.from("family_members")
                    .select {
                        filter { eq("user_id", userId) }
                        filter { eq("role", "receiver") }
                        filter { eq("status", "active") }
                    }
                    .decodeSingleOrNull<FamilyMember>()

                if (member == null) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        errorMessage = "No family membership found."
                    )
                    return@launch
                }

                val settings = supabase.postgrest.from("receiver_settings")
                    .select {
                        filter { eq("family_member_id", member.id) }
                    }
                    .decodeSingleOrNull<ReceiverSettings>()

                val todayCheckIn = checkInService.todayCheckInStatus(userId, member.familyId)

                val pendingRequest = if (todayCheckIn == null) {
                    checkInService.getTodayPendingRequest(userId, member.familyId)
                } else null

                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    familyId = member.familyId,
                    receiverId = userId,
                    hasCheckedInToday = todayCheckIn != null,
                    lastCheckIn = todayCheckIn,
                    pendingRequestId = pendingRequest?.id,
                    nextCheckInTime = computeNextCheckInTime(settings),
                    receiverName = member.user?.displayName ?: "",
                    isKidMode = settings?.receiverMode == net.wellvo.android.data.models.ReceiverMode.Kid
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = e.message ?: "Failed to load check-in status."
                )
            }
        }
    }

    fun checkIn() {
        val state = _uiState.value
        val familyId = state.familyId ?: return
        val receiverId = state.receiverId ?: return
        val requestId = state.pendingRequestId

        if (requestId == null) {
            _uiState.value = state.copy(errorMessage = "No pending check-in request.")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isCheckingIn = true, errorMessage = null)
            try {
                checkInService.checkIn(
                    familyId = familyId,
                    receiverId = receiverId,
                    requestId = requestId,
                    mood = state.selectedMood?.name?.lowercase(),
                    source = "app"
                )

                val updatedCheckIn = checkInService.todayCheckInStatus(receiverId, familyId)

                _uiState.value = _uiState.value.copy(
                    isCheckingIn = false,
                    hasCheckedInToday = true,
                    lastCheckIn = updatedCheckIn,
                    showMoodSelector = true
                )
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(
                    isCheckingIn = false,
                    errorMessage = e.localizedMessage
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isCheckingIn = false,
                    errorMessage = e.message ?: "Check-in failed."
                )
            }
        }
    }

    fun selectMood(mood: Mood) {
        _uiState.value = _uiState.value.copy(selectedMood = mood)
    }

    fun submitMood() {
        val mood = _uiState.value.selectedMood ?: return
        val checkIn = _uiState.value.lastCheckIn ?: return

        viewModelScope.launch {
            try {
                supabase.postgrest.from("checkins")
                    .update(kotlinx.serialization.json.buildJsonObject {
                        put("mood", kotlinx.serialization.json.JsonPrimitive(mood.name.lowercase()))
                    }) {
                        filter { eq("id", checkIn.id) }
                    }
                _uiState.value = _uiState.value.copy(
                    showMoodSelector = false,
                    lastCheckIn = checkIn.copy(mood = mood),
                    showLocationSelector = _uiState.value.isKidMode,
                    showKidResponseButtons = false
                )
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(
                    showMoodSelector = false,
                    showLocationSelector = _uiState.value.isKidMode
                )
            }
        }
    }

    fun skipMood() {
        _uiState.value = _uiState.value.copy(
            showMoodSelector = false,
            showLocationSelector = _uiState.value.isKidMode
        )
    }

    fun selectLocationLabel(label: String) {
        _uiState.value = _uiState.value.copy(selectedLocationLabel = label)
    }

    fun submitLocationLabel() {
        val label = _uiState.value.selectedLocationLabel ?: return
        val checkIn = _uiState.value.lastCheckIn ?: return

        viewModelScope.launch {
            try {
                supabase.postgrest.from("checkins")
                    .update(kotlinx.serialization.json.buildJsonObject {
                        put("location_label", kotlinx.serialization.json.JsonPrimitive(label))
                    }) {
                        filter { eq("id", checkIn.id) }
                    }
                _uiState.value = _uiState.value.copy(
                    showLocationSelector = false,
                    showKidResponseButtons = true,
                    lastCheckIn = checkIn.copy(locationLabel = label)
                )
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(
                    showLocationSelector = false,
                    showKidResponseButtons = true
                )
            }
        }
    }

    fun skipLocationLabel() {
        _uiState.value = _uiState.value.copy(
            showLocationSelector = false,
            showKidResponseButtons = true
        )
    }

    fun selectKidResponse(response: String) {
        _uiState.value = _uiState.value.copy(selectedKidResponse = response)
    }

    fun submitKidResponse() {
        val response = _uiState.value.selectedKidResponse ?: return
        val checkIn = _uiState.value.lastCheckIn ?: return

        viewModelScope.launch {
            try {
                supabase.postgrest.from("checkins")
                    .update(kotlinx.serialization.json.buildJsonObject {
                        put("kid_response_type", kotlinx.serialization.json.JsonPrimitive(response))
                    }) {
                        filter { eq("id", checkIn.id) }
                    }
                _uiState.value = _uiState.value.copy(
                    showKidResponseButtons = false,
                    lastCheckIn = checkIn.copy(kidResponseType = response)
                )
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(showKidResponseButtons = false)
            }
        }
    }

    fun skipKidResponse() {
        _uiState.value = _uiState.value.copy(showKidResponseButtons = false)
    }

    fun retry() {
        loadReceiverState()
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    private fun computeNextCheckInTime(settings: ReceiverSettings?): String? {
        if (settings == null) return null
        if (settings.schedulePaused) return "Notifications paused"

        val tz = try {
            ZoneId.of(settings.timezone)
        } catch (_: Exception) {
            ZoneId.systemDefault()
        }

        val now = java.time.ZonedDateTime.now(tz)
        val today = now.toLocalDate()

        return when (settings.scheduleType) {
            ScheduleType.Daily -> {
                val time = parseTime(settings.checkinTime)
                if (time != null && now.toLocalTime().isBefore(time)) {
                    formatTimeDisplay(time) + " today"
                } else {
                    formatTimeDisplay(time ?: LocalTime.of(9, 0)) + " tomorrow"
                }
            }
            ScheduleType.WeekdayWeekend -> {
                val isWeekend = today.dayOfWeek == DayOfWeek.SATURDAY || today.dayOfWeek == DayOfWeek.SUNDAY
                val timeStr = if (isWeekend) settings.weekendCheckinTime ?: settings.checkinTime else settings.checkinTime
                val time = parseTime(timeStr)
                if (time != null && now.toLocalTime().isBefore(time)) {
                    formatTimeDisplay(time) + " today"
                } else {
                    val tomorrow = today.plusDays(1)
                    val isTomorrowWeekend = tomorrow.dayOfWeek == DayOfWeek.SATURDAY || tomorrow.dayOfWeek == DayOfWeek.SUNDAY
                    val tomorrowTimeStr = if (isTomorrowWeekend) settings.weekendCheckinTime ?: settings.checkinTime else settings.checkinTime
                    formatTimeDisplay(parseTime(tomorrowTimeStr) ?: LocalTime.of(9, 0)) + " tomorrow"
                }
            }
            ScheduleType.Custom -> {
                val schedule = settings.customSchedule ?: return formatTimeDisplay(parseTime(settings.checkinTime) ?: LocalTime.of(9, 0))
                // Find next enabled day
                for (daysAhead in 0..7) {
                    val checkDate = today.plusDays(daysAhead.toLong())
                    val dayKey = checkDate.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.ENGLISH).lowercase().take(3)
                    val dayTime = schedule.timeForDay(dayKey)
                    if (dayTime != null) {
                        val time = parseTime(dayTime)
                        if (daysAhead == 0 && time != null && now.toLocalTime().isBefore(time)) {
                            return formatTimeDisplay(time) + " today"
                        } else if (daysAhead > 0 && time != null) {
                            val dayName = checkDate.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.ENGLISH)
                            return formatTimeDisplay(time) + " $dayName"
                        }
                    }
                }
                formatTimeDisplay(parseTime(settings.checkinTime) ?: LocalTime.of(9, 0))
            }
        }
    }

    private fun parseTime(time: String): LocalTime? {
        val parts = time.split(":")
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        return LocalTime.of(hour, minute)
    }

    private fun formatTimeDisplay(time: LocalTime): String {
        val hour = time.hour
        val minute = time.minute
        val amPm = if (hour < 12) "AM" else "PM"
        val displayHour = when {
            hour == 0 -> 12
            hour > 12 -> hour - 12
            else -> hour
        }
        return "%d:%02d %s".format(displayHour, minute, amPm)
    }
}
