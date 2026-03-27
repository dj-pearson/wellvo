package net.wellvo.android.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ReceiverSettings(
    val id: String,
    @SerialName("family_member_id")
    val familyMemberId: String,
    @SerialName("checkin_time")
    val checkinTime: String,
    val timezone: String,
    @SerialName("grace_period_minutes")
    val gracePeriodMinutes: Int,
    @SerialName("reminder_interval_minutes")
    val reminderIntervalMinutes: Int,
    @SerialName("escalation_enabled")
    val escalationEnabled: Boolean,
    @SerialName("quiet_hours_start")
    val quietHoursStart: String? = null,
    @SerialName("quiet_hours_end")
    val quietHoursEnd: String? = null,
    @SerialName("mood_tracking_enabled")
    val moodTrackingEnabled: Boolean,
    @SerialName("sms_escalation_enabled")
    val smsEscalationEnabled: Boolean,
    @SerialName("is_active")
    val isActive: Boolean,
    @SerialName("location_tracking_enabled")
    val locationTrackingEnabled: Boolean,
    @SerialName("home_latitude")
    val homeLatitude: Double? = null,
    @SerialName("home_longitude")
    val homeLongitude: Double? = null,
    @SerialName("geofence_radius_meters")
    val geofenceRadiusMeters: Int,
    @SerialName("location_alert_enabled")
    val locationAlertEnabled: Boolean,
    @SerialName("receiver_mode")
    val receiverMode: ReceiverMode,
    @SerialName("schedule_type")
    val scheduleType: ScheduleType,
    @SerialName("weekend_checkin_time")
    val weekendCheckinTime: String? = null,
    @SerialName("custom_schedule")
    val customSchedule: DaySchedule? = null,
    @SerialName("schedule_paused")
    val schedulePaused: Boolean
)

@Serializable
data class DaySchedule(
    val mon: String? = null,
    val tue: String? = null,
    val wed: String? = null,
    val thu: String? = null,
    val fri: String? = null,
    val sat: String? = null,
    val sun: String? = null
) {
    companion object {
        val weekdays = listOf("mon", "tue", "wed", "thu", "fri")
        val weekend = listOf("sat", "sun")
        val allDays = weekdays + weekend
    }

    fun timeForDay(day: String): String? = when (day) {
        "mon" -> mon
        "tue" -> tue
        "wed" -> wed
        "thu" -> thu
        "fri" -> fri
        "sat" -> sat
        "sun" -> sun
        else -> null
    }
}

@Serializable
enum class ReceiverMode {
    @SerialName("standard") Standard,
    @SerialName("kid") Kid;

    val displayName: String
        get() = when (this) {
            Standard -> "Standard"
            Kid -> "Kid"
        }
}

@Serializable
enum class ScheduleType {
    @SerialName("daily") Daily,
    @SerialName("weekday_weekend") WeekdayWeekend,
    @SerialName("custom") Custom;

    val displayName: String
        get() = when (this) {
            Daily -> "Daily"
            WeekdayWeekend -> "Weekday/Weekend"
            Custom -> "Custom"
        }
}
