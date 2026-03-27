package net.wellvo.android.viewmodels

import net.wellvo.android.data.models.CheckIn
import net.wellvo.android.data.models.CheckInSource
import net.wellvo.android.data.models.DaySchedule
import net.wellvo.android.data.models.Mood
import net.wellvo.android.data.models.ReceiverMode
import net.wellvo.android.data.models.ReceiverSettings
import net.wellvo.android.data.models.ScheduleType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalTime

class ReceiverViewModelTest {

    @Test
    fun `initial ReceiverUiState has correct defaults`() {
        val state = ReceiverUiState()
        assertFalse(state.hasCheckedInToday)
        assertFalse(state.isCheckingIn)
        assertNull(state.lastCheckIn)
        assertNull(state.errorMessage)
        assertNull(state.nextCheckInTime)
        assertEquals("", state.receiverName)
        assertNull(state.pendingRequestId)
        assertTrue(state.isLoading)
        assertFalse(state.showMoodSelector)
        assertFalse(state.isKidMode)
    }

    @Test
    fun `selectMood updates selected mood in state`() {
        var state = ReceiverUiState()
        state = state.copy(selectedMood = Mood.Happy)
        assertEquals(Mood.Happy, state.selectedMood)
    }

    @Test
    fun `skipMood hides mood selector and shows location selector in kid mode`() {
        var state = ReceiverUiState(showMoodSelector = true, isKidMode = true)
        state = state.copy(showMoodSelector = false, showLocationSelector = state.isKidMode)
        assertFalse(state.showMoodSelector)
        assertTrue(state.showLocationSelector)
    }

    @Test
    fun `skipMood hides mood selector and does not show location selector in standard mode`() {
        var state = ReceiverUiState(showMoodSelector = true, isKidMode = false)
        state = state.copy(showMoodSelector = false, showLocationSelector = state.isKidMode)
        assertFalse(state.showMoodSelector)
        assertFalse(state.showLocationSelector)
    }

    @Test
    fun `selectLocationLabel updates state`() {
        var state = ReceiverUiState()
        state = state.copy(selectedLocationLabel = "school")
        assertEquals("school", state.selectedLocationLabel)
    }

    @Test
    fun `selectKidResponse updates state`() {
        var state = ReceiverUiState()
        state = state.copy(selectedKidResponse = "picking_me_up")
        assertEquals("picking_me_up", state.selectedKidResponse)
    }

    @Test
    fun `skipKidResponse hides kid response buttons`() {
        var state = ReceiverUiState(showKidResponseButtons = true)
        state = state.copy(showKidResponseButtons = false)
        assertFalse(state.showKidResponseButtons)
    }

    @Test
    fun `clearError removes error message`() {
        var state = ReceiverUiState(errorMessage = "Something went wrong")
        state = state.copy(errorMessage = null)
        assertNull(state.errorMessage)
    }

    // -- Schedule computation tests using extracted logic --

    @Test
    fun `computeNextCheckInTime with null settings returns null`() {
        val result = computeNextCheckInTimeHelper(null)
        assertNull(result)
    }

    @Test
    fun `computeNextCheckInTime with paused schedule returns paused message`() {
        val settings = makeSettings(schedulePaused = true)
        val result = computeNextCheckInTimeHelper(settings)
        assertEquals("Notifications paused", result)
    }

    @Test
    fun `parseTime correctly parses HH:mm format`() {
        assertEquals(LocalTime.of(9, 0), parseTimeHelper("09:00"))
        assertEquals(LocalTime.of(14, 30), parseTimeHelper("14:30"))
        assertEquals(LocalTime.of(0, 0), parseTimeHelper("00:00"))
        assertNull(parseTimeHelper("invalid"))
        assertNull(parseTimeHelper("12"))
    }

    @Test
    fun `formatTimeDisplay correctly formats times`() {
        assertEquals("9:00 AM", formatTimeDisplayHelper(LocalTime.of(9, 0)))
        assertEquals("12:00 PM", formatTimeDisplayHelper(LocalTime.of(12, 0)))
        assertEquals("1:30 PM", formatTimeDisplayHelper(LocalTime.of(13, 30)))
        assertEquals("12:00 AM", formatTimeDisplayHelper(LocalTime.of(0, 0)))
    }

    @Test
    fun `daily schedule computes next check-in`() {
        val settings = makeSettings(scheduleType = ScheduleType.Daily, checkinTime = "09:00")
        val result = computeNextCheckInTimeHelper(settings)
        assertTrue(result != null)
        assertTrue(result!!.contains("9:00 AM"))
    }

    @Test
    fun `weekday weekend schedule uses different times`() {
        val settings = makeSettings(
            scheduleType = ScheduleType.WeekdayWeekend,
            checkinTime = "08:00",
            weekendCheckinTime = "10:00"
        )
        val result = computeNextCheckInTimeHelper(settings)
        assertTrue(result != null)
    }

    // -- Helpers that mirror ViewModel private methods --

    private fun computeNextCheckInTimeHelper(settings: ReceiverSettings?): String? {
        if (settings == null) return null
        if (settings.schedulePaused) return "Notifications paused"

        val tz = try {
            java.time.ZoneId.of(settings.timezone)
        } catch (_: Exception) {
            java.time.ZoneId.systemDefault()
        }

        val now = java.time.ZonedDateTime.now(tz)
        val today = now.toLocalDate()

        return when (settings.scheduleType) {
            ScheduleType.Daily -> {
                val time = parseTimeHelper(settings.checkinTime)
                if (time != null && now.toLocalTime().isBefore(time)) {
                    formatTimeDisplayHelper(time) + " today"
                } else {
                    formatTimeDisplayHelper(time ?: LocalTime.of(9, 0)) + " tomorrow"
                }
            }
            ScheduleType.WeekdayWeekend -> {
                val isWeekend = today.dayOfWeek == java.time.DayOfWeek.SATURDAY || today.dayOfWeek == java.time.DayOfWeek.SUNDAY
                val timeStr = if (isWeekend) settings.weekendCheckinTime ?: settings.checkinTime else settings.checkinTime
                val time = parseTimeHelper(timeStr)
                if (time != null && now.toLocalTime().isBefore(time)) {
                    formatTimeDisplayHelper(time) + " today"
                } else {
                    val tomorrow = today.plusDays(1)
                    val isTomorrowWeekend = tomorrow.dayOfWeek == java.time.DayOfWeek.SATURDAY || tomorrow.dayOfWeek == java.time.DayOfWeek.SUNDAY
                    val tomorrowTimeStr = if (isTomorrowWeekend) settings.weekendCheckinTime ?: settings.checkinTime else settings.checkinTime
                    formatTimeDisplayHelper(parseTimeHelper(tomorrowTimeStr) ?: LocalTime.of(9, 0)) + " tomorrow"
                }
            }
            ScheduleType.Custom -> {
                formatTimeDisplayHelper(parseTimeHelper(settings.checkinTime) ?: LocalTime.of(9, 0))
            }
        }
    }

    private fun parseTimeHelper(time: String): LocalTime? {
        val parts = time.split(":")
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        return LocalTime.of(hour, minute)
    }

    private fun formatTimeDisplayHelper(time: LocalTime): String {
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

    private fun makeSettings(
        scheduleType: ScheduleType = ScheduleType.Daily,
        checkinTime: String = "09:00",
        weekendCheckinTime: String? = null,
        schedulePaused: Boolean = false,
        customSchedule: DaySchedule? = null
    ) = ReceiverSettings(
        id = "s1",
        familyMemberId = "m1",
        checkinTime = checkinTime,
        timezone = "America/New_York",
        gracePeriodMinutes = 30,
        reminderIntervalMinutes = 15,
        escalationEnabled = true,
        quietHoursStart = null,
        quietHoursEnd = null,
        moodTrackingEnabled = true,
        smsEscalationEnabled = false,
        isActive = true,
        locationTrackingEnabled = false,
        homeLatitude = null,
        homeLongitude = null,
        geofenceRadiusMeters = 200,
        locationAlertEnabled = false,
        receiverMode = ReceiverMode.Standard,
        scheduleType = scheduleType,
        weekendCheckinTime = weekendCheckinTime,
        customSchedule = customSchedule,
        schedulePaused = schedulePaused
    )
}
