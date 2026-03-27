package net.wellvo.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import net.wellvo.android.data.models.DaySchedule
import net.wellvo.android.data.models.ReceiverMode
import net.wellvo.android.data.models.ReceiverSettings
import net.wellvo.android.data.models.ScheduleType
import net.wellvo.android.network.WellvoError
import net.wellvo.android.services.CheckInService
import javax.inject.Inject

@HiltViewModel
class ReceiverSettingsViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val checkInService: CheckInService
) : ViewModel() {

    private val _settings = MutableStateFlow<ReceiverSettings?>(null)
    val settings: StateFlow<ReceiverSettings?> = _settings.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isSaving = MutableStateFlow(false)
    val isSaving: StateFlow<Boolean> = _isSaving.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _successMessage = MutableStateFlow<String?>(null)
    val successMessage: StateFlow<String?> = _successMessage.asStateFlow()

    private val _isSendingManual = MutableStateFlow(false)
    val isSendingManual: StateFlow<Boolean> = _isSendingManual.asStateFlow()

    // Editable state
    val schedulePaused = MutableStateFlow(false)
    val scheduleType = MutableStateFlow(ScheduleType.Daily)
    val checkinHour = MutableStateFlow(8)
    val checkinMinute = MutableStateFlow(0)
    val weekendHour = MutableStateFlow(10)
    val weekendMinute = MutableStateFlow(0)
    val customDayEnabled = MutableStateFlow(
        mapOf("mon" to true, "tue" to true, "wed" to true, "thu" to true, "fri" to true, "sat" to true, "sun" to true)
    )
    val customDayHours = MutableStateFlow(
        mapOf("mon" to 8, "tue" to 8, "wed" to 8, "thu" to 8, "fri" to 8, "sat" to 10, "sun" to 10)
    )
    val customDayMinutes = MutableStateFlow(
        mapOf("mon" to 0, "tue" to 0, "wed" to 0, "thu" to 0, "fri" to 0, "sat" to 0, "sun" to 0)
    )
    val receiverMode = MutableStateFlow(ReceiverMode.Standard)
    val gracePeriodMinutes = MutableStateFlow(30)
    val reminderIntervalMinutes = MutableStateFlow(30)
    val escalationEnabled = MutableStateFlow(true)
    val quietHoursEnabled = MutableStateFlow(false)
    val quietHoursStartHour = MutableStateFlow(22)
    val quietHoursStartMinute = MutableStateFlow(0)
    val quietHoursEndHour = MutableStateFlow(7)
    val quietHoursEndMinute = MutableStateFlow(0)
    val smsEscalationEnabled = MutableStateFlow(false)
    val moodTrackingEnabled = MutableStateFlow(false)

    private var familyMemberId: String? = null
    private var familyId: String? = null
    private var receiverId: String? = null

    fun loadSettings(memberId: String) {
        familyMemberId = memberId
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val result = supabase.postgrest.from("receiver_settings")
                    .select {
                        filter { eq("family_member_id", memberId) }
                    }
                    .decodeSingleOrNull<ReceiverSettings>()

                result?.let { s ->
                    _settings.value = s
                    schedulePaused.value = s.schedulePaused
                    scheduleType.value = s.scheduleType
                    receiverMode.value = s.receiverMode
                    gracePeriodMinutes.value = s.gracePeriodMinutes
                    reminderIntervalMinutes.value = s.reminderIntervalMinutes
                    escalationEnabled.value = s.escalationEnabled
                    moodTrackingEnabled.value = s.moodTrackingEnabled
                    smsEscalationEnabled.value = s.smsEscalationEnabled
                    quietHoursEnabled.value = s.quietHoursStart != null

                    // Parse checkin time
                    parseTime(s.checkinTime)?.let { (h, m) ->
                        checkinHour.value = h
                        checkinMinute.value = m
                    }

                    // Parse weekend time
                    s.weekendCheckinTime?.let { wt ->
                        parseTime(wt)?.let { (h, m) ->
                            weekendHour.value = h
                            weekendMinute.value = m
                        }
                    }

                    // Parse quiet hours
                    s.quietHoursStart?.let { qs ->
                        parseTime(qs)?.let { (h, m) ->
                            quietHoursStartHour.value = h
                            quietHoursStartMinute.value = m
                        }
                    }
                    s.quietHoursEnd?.let { qe ->
                        parseTime(qe)?.let { (h, m) ->
                            quietHoursEndHour.value = h
                            quietHoursEndMinute.value = m
                        }
                    }

                    // Parse custom schedule
                    s.customSchedule?.let { cs ->
                        val enabled = mutableMapOf<String, Boolean>()
                        val hours = mutableMapOf<String, Int>()
                        val minutes = mutableMapOf<String, Int>()
                        for (day in DaySchedule.allDays) {
                            val time = cs.timeForDay(day)
                            enabled[day] = time != null
                            val parsed = time?.let { parseTime(it) }
                            hours[day] = parsed?.first ?: 8
                            minutes[day] = parsed?.second ?: 0
                        }
                        customDayEnabled.value = enabled
                        customDayHours.value = hours
                        customDayMinutes.value = minutes
                    }
                }
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load settings."
            }
            _isLoading.value = false
        }
    }

    fun loadForReceiver(memberId: String, famId: String, recId: String) {
        familyId = famId
        receiverId = recId
        loadSettings(memberId)
    }

    fun saveSettings() {
        val memberId = familyMemberId ?: return
        viewModelScope.launch {
            _isSaving.value = true
            try {
                val checkinTimeStr = "%02d:%02d".format(checkinHour.value, checkinMinute.value)
                val weekendTimeStr = "%02d:%02d".format(weekendHour.value, weekendMinute.value)
                val quietStart = if (quietHoursEnabled.value) "%02d:%02d".format(quietHoursStartHour.value, quietHoursStartMinute.value) else null
                val quietEnd = if (quietHoursEnabled.value) "%02d:%02d".format(quietHoursEndHour.value, quietHoursEndMinute.value) else null

                val updateObj = buildJsonObject {
                    put("schedule_paused", schedulePaused.value)
                    put("schedule_type", when (scheduleType.value) {
                        ScheduleType.Daily -> "daily"
                        ScheduleType.WeekdayWeekend -> "weekday_weekend"
                        ScheduleType.Custom -> "custom"
                    })
                    put("checkin_time", checkinTimeStr)
                    put("weekend_checkin_time", weekendTimeStr)
                    put("receiver_mode", if (receiverMode.value == ReceiverMode.Kid) "kid" else "standard")
                    put("grace_period_minutes", gracePeriodMinutes.value)
                    put("reminder_interval_minutes", reminderIntervalMinutes.value)
                    put("escalation_enabled", escalationEnabled.value)
                    put("quiet_hours_start", quietStart)
                    put("quiet_hours_end", quietEnd)
                    put("sms_escalation_enabled", smsEscalationEnabled.value)
                    put("mood_tracking_enabled", moodTrackingEnabled.value)

                    if (scheduleType.value == ScheduleType.Custom) {
                        putJsonObject("custom_schedule") {
                            for (day in DaySchedule.allDays) {
                                if (customDayEnabled.value[day] == true) {
                                    put(day, "%02d:%02d".format(
                                        customDayHours.value[day] ?: 8,
                                        customDayMinutes.value[day] ?: 0
                                    ))
                                }
                            }
                        }
                    }
                }

                supabase.postgrest.from("receiver_settings")
                    .update(updateObj) {
                        filter { eq("family_member_id", memberId) }
                    }

                _successMessage.value = "Settings saved."
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to save settings."
            }
            _isSaving.value = false
        }
    }

    fun sendManualCheckIn() {
        val famId = familyId ?: return
        val recId = receiverId ?: return
        viewModelScope.launch {
            _isSendingManual.value = true
            try {
                checkInService.sendOnDemandCheckIn(familyId = famId, receiverId = recId)
                _successMessage.value = "Check-in request sent."
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to send check-in."
            }
            _isSendingManual.value = false
        }
    }

    fun clearError() { _errorMessage.value = null }
    fun clearSuccessMessage() { _successMessage.value = null }

    private fun parseTime(time: String): Pair<Int, Int>? {
        val parts = time.split(":")
        if (parts.size >= 2) {
            val h = parts[0].toIntOrNull() ?: return null
            val m = parts[1].toIntOrNull() ?: return null
            return h to m
        }
        return null
    }
}
