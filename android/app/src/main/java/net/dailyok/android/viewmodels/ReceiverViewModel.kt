package net.dailyok.android.viewmodels

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
import net.dailyok.android.data.models.CheckIn
import net.dailyok.android.data.models.CheckInRequest
import net.dailyok.android.data.models.DaySchedule
import io.github.jan.supabase.postgrest.query.Columns
import net.dailyok.android.data.models.FamilyMember
import net.dailyok.android.data.models.Mood
import net.dailyok.android.data.models.ReceiverSettings
import net.dailyok.android.data.models.ScheduleType
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale
import net.dailyok.android.network.DailyOKError
import net.dailyok.android.services.AnalyticsService
import net.dailyok.android.services.CheckInService
import net.dailyok.android.services.OfflineCheckInService
import androidx.compose.runtime.Immutable
import javax.inject.Inject

@Immutable
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
    val showKidResponseButtons: Boolean = false,
    val streakDays: Int = 0,
    val consistencyPercent: Int = 0,
    /** A help request / call-me / SOS / kid reply is on its way. */
    val isSendingHelp: Boolean = false,
    /** What was sent, in the receiver's words ("We told your family you need help."). */
    val helpSentMessage: String? = null,
    /** A help send that failed. Never queued: shown with "call instead". */
    val helpFailureMessage: String? = null,
    /** The urgent kind behind helpSentMessage / helpFailureMessage, for "Text <owner>". */
    val lastHelpKind: ReceiverHelpKind? = null,
    /** The family owner's name, for "Text <owner>". Null when unknown. */
    val ownerName: String? = null,
    /**
     * The owner's number (family_contact_numbers, 00067: a receiver gets its
     * caregivers' numbers only). Null hides "Text <owner>".
     */
    val ownerPhone: String? = null
) {
    /**
     * "Text <owner>" under a help result: only for urgent kinds (a text can
     * still get through when Daily OK can't) and only with a dialable number.
     */
    val canTextOwnerAboutHelp: Boolean
        get() = lastHelpKind?.isUrgent == true &&
            (helpSentMessage != null || helpFailureMessage != null) &&
            net.dailyok.android.util.FamilyText.dialable(ownerPhone) != null

    /** The pre-filled "I need help" text for the owner, with a rough map link when known. */
    fun helpTextForOwner(): String = net.dailyok.android.util.FamilyText.askingForHelp(
        ownerName = ownerName,
        callMe = lastHelpKind == ReceiverHelpKind.CallMe,
        latitude = lastCheckIn?.latitude,
        longitude = lastCheckIn?.longitude
    )
}

/**
 * Something the receiver sends besides "I'm OK". Help / call-me / SOS page the
 * family at once; pick-up and stay-longer are kid quick replies. All of them
 * go through process-checkin-response, which records them and alerts the
 * family — never a direct database write (that alerted nobody) and never the
 * offline queue (a help request delivered hours later is worse than one the
 * receiver knows didn't send). Same set as iOS ReceiverHelpKind.
 */
enum class ReceiverHelpKind(
    /** process-checkin-response `response_type`. */
    val responseType: String,
    /** process-checkin-response `kid_response_type`, if any. */
    val kidResponseType: String?
) {
    NeedHelp("need_help", null),
    CallMe("call_me", null),
    Sos("ok", "sos"),
    PickMeUp("ok", "picking_me_up"),
    StayLonger("ok", "can_stay_longer");

    /** Pages the family with an urgent alert. Confirmed before sending. */
    val isUrgent: Boolean get() = this == NeedHelp || this == CallMe || this == Sos

    fun sentMessage(): String = when (this) {
        NeedHelp, Sos -> "We told your family you need help."
        CallMe -> "We asked your family to call you."
        PickMeUp -> "We told your family you'd like to be picked up."
        StayLonger -> "We asked your family if you can stay longer."
    }

    companion object {
        fun fromKidResponse(raw: String): ReceiverHelpKind? = entries.firstOrNull { it.kidResponseType == raw }
    }
}

@HiltViewModel
class ReceiverViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val checkInService: CheckInService,
    private val offlineCheckInService: OfflineCheckInService,
    private val analyticsService: AnalyticsService
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
                    .select(columns = Columns.raw(FamilyMember.COLUMNS)) {
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

                // "Today" is the receiver's local day, not the device's, so a
                // user who travelled to a different timezone (or mistakenly
                // has a device TZ that disagrees with their profile) still
                // sees the correct state.
                val todayCheckIn = checkInService.todayCheckInStatus(
                    userId,
                    member.familyId,
                    settings?.timezone
                )
                android.util.Log.d(
                    "ReceiverViewModel",
                    "loadReceiverState: tz=${settings?.timezone} todayCheckIn=${todayCheckIn?.checkedInAt}"
                )

                val pendingRequest = if (todayCheckIn == null) {
                    checkInService.getTodayPendingRequest(userId, member.familyId)
                } else null

                // Streak + 7-day consistency from the receiver's own 30-day
                // history. Failures are non-fatal — chips just stay hidden.
                val (streakDays, consistencyPercent) = try {
                    val history = checkInService.checkInHistory(userId, member.familyId, 30)
                    val timestamps = history.map { it.checkedInAt }
                    net.dailyok.android.util.Streaks.currentStreak(timestamps) to
                        net.dailyok.android.util.Streaks.consistencyPercent(timestamps, windowDays = 7)
                } catch (_: Exception) {
                    0 to 0
                }

                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    familyId = member.familyId,
                    receiverId = userId,
                    hasCheckedInToday = todayCheckIn != null,
                    lastCheckIn = todayCheckIn,
                    pendingRequestId = pendingRequest?.id,
                    nextCheckInTime = computeNextCheckInTime(settings),
                    receiverName = member.user?.displayName ?: "",
                    isKidMode = settings?.receiverMode == net.dailyok.android.data.models.ReceiverMode.Kid,
                    streakDays = streakDays,
                    consistencyPercent = consistencyPercent
                )
                loadOwnerContact(member.familyId)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = e.message ?: "Failed to load check-in status."
                )
            }
        }
    }

    @kotlinx.serialization.Serializable
    private data class OwnerIdRow(@kotlinx.serialization.SerialName("owner_id") val ownerId: String)

    @kotlinx.serialization.Serializable
    private data class NameRow(@kotlinx.serialization.SerialName("display_name") val displayName: String? = null)

    /**
     * The owner's name (their public profile) and number (from
     * family_contact_numbers, which gives a receiver its caregivers' numbers
     * only). Best-effort: a failure keeps whatever was loaded before.
     */
    private suspend fun loadOwnerContact(familyId: String) {
        try {
            val ownerId = supabase.postgrest.from("families")
                .select(columns = Columns.list("owner_id")) {
                    filter { eq("id", familyId) }
                    limit(1)
                }
                .decodeList<OwnerIdRow>()
                .firstOrNull()
                ?.ownerId ?: return
            val name = try {
                supabase.postgrest.from("users")
                    .select(columns = Columns.list("display_name")) {
                        filter { eq("id", ownerId) }
                        limit(1)
                    }
                    .decodeList<NameRow>()
                    .firstOrNull()
                    ?.displayName
                    ?.let { net.dailyok.android.network.JoinPreview.presentableName(it) }
            } catch (_: Exception) { null }
            val phones = net.dailyok.android.network.MemberDirectory
                .contactNumbersOrEmpty(supabase, familyId, listOf(ownerId))
            val current = _uiState.value
            _uiState.value = current.copy(
                ownerName = name ?: current.ownerName,
                ownerPhone = if (phones.isEmpty()) current.ownerPhone else phones[ownerId]
            )
        } catch (_: Exception) { /* best-effort */ }
    }

    fun checkIn() {
        val state = _uiState.value
        val familyId = state.familyId ?: return
        val receiverId = state.receiverId ?: return
        // `requestId` is optional — when the user taps "I'm OK" outside of a
        // scheduled/on-demand notification there's no pending request row, so
        // the edge function records the check-in via receiver_id+family_id.
        val requestId = state.pendingRequestId

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

                analyticsService.track(AnalyticsService.CHECK_IN_COMPLETED)
                val updatedCheckIn = checkInService.todayCheckInStatus(receiverId, familyId)

                _uiState.value = _uiState.value.copy(
                    isCheckingIn = false,
                    hasCheckedInToday = true,
                    lastCheckIn = updatedCheckIn,
                    pendingRequestId = null,
                    showMoodSelector = true
                )
            } catch (e: DailyOKError) {
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
                analyticsService.track(AnalyticsService.MOOD_SUBMITTED, mapOf("mood" to mood.name))
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

    /**
     * A kid quick reply after checking in (pick me up / can I stay longer /
     * SOS). Sent through process-checkin-response like every help signal, so
     * the family is actually told. It used to be a direct UPDATE of the
     * check-in row: the dashboard showed a badge, but no alert and no push
     * went out — an SOS reached nobody.
     */
    fun submitKidResponse() {
        val response = _uiState.value.selectedKidResponse ?: return
        val kind = ReceiverHelpKind.fromKidResponse(response) ?: return
        sendHelp(kind)
    }

    /**
     * Send a help request, call-me, SOS or kid reply. Live only: an urgent
     * signal is never queued for silent later delivery. A failure says so and
     * suggests calling instead.
     */
    fun sendHelp(kind: ReceiverHelpKind) {
        val state = _uiState.value
        val familyId = state.familyId ?: return
        val receiverId = state.receiverId ?: return
        if (state.isSendingHelp) return

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isSendingHelp = true,
                helpSentMessage = null,
                helpFailureMessage = null,
                lastHelpKind = kind
            )
            try {
                checkInService.checkIn(
                    familyId = familyId,
                    receiverId = receiverId,
                    // Not tied to a pending request: the server records a
                    // check-in if there is none today, or applies this as a
                    // follow-up to today's and alerts the family either way.
                    requestId = null,
                    source = "app",
                    kidResponseType = kind.kidResponseType,
                    responseType = kind.responseType,
                    locationLabel = _uiState.value.lastCheckIn?.locationLabel
                )
                analyticsService.track(AnalyticsService.CHECK_IN_COMPLETED, mapOf("help" to kind.name))
                val refreshed = try {
                    checkInService.todayCheckInStatus(receiverId, familyId)
                } catch (_: Exception) { null }
                val current = _uiState.value
                _uiState.value = current.copy(
                    isSendingHelp = false,
                    hasCheckedInToday = true,
                    pendingRequestId = null,
                    lastCheckIn = refreshed ?: current.lastCheckIn?.let { row ->
                        if (kind.kidResponseType != null) row.copy(kidResponseType = kind.kidResponseType) else row
                    },
                    showKidResponseButtons = false,
                    selectedKidResponse = null,
                    helpSentMessage = kind.sentMessage()
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isSendingHelp = false,
                    helpFailureMessage = helpFailureMessage(e)
                )
            }
        }
    }

    fun clearHelpMessages() {
        _uiState.value = _uiState.value.copy(helpSentMessage = null, helpFailureMessage = null, lastHelpKind = null)
    }

    private fun helpFailureMessage(e: Exception): String = when (e) {
        is DailyOKError.Offline, is DailyOKError.Network ->
            "Not sent — your phone is offline. Call your family instead."
        else -> "Not sent — Daily OK couldn't be reached. Call your family instead."
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
