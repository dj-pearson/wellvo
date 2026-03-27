package net.wellvo.android.ui.screens.owner

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import net.wellvo.android.data.models.DaySchedule
import net.wellvo.android.data.models.ReceiverMode
import net.wellvo.android.data.models.ScheduleType
import net.wellvo.android.viewmodels.ReceiverSettingsViewModel

private val SectionGreen = Color(0xFF22C55E)

@Composable
fun ReceiverSettingsScreen(
    viewModel: ReceiverSettingsViewModel,
    memberId: String,
    familyId: String,
    receiverId: String,
    receiverName: String,
    modifier: Modifier = Modifier
) {
    val settings by viewModel.settings.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isSaving by viewModel.isSaving.collectAsState()
    val isSendingManual by viewModel.isSendingManual.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val successMessage by viewModel.successMessage.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    val schedulePaused by viewModel.schedulePaused.collectAsState()
    val scheduleType by viewModel.scheduleType.collectAsState()
    val checkinHour by viewModel.checkinHour.collectAsState()
    val checkinMinute by viewModel.checkinMinute.collectAsState()
    val weekendHour by viewModel.weekendHour.collectAsState()
    val weekendMinute by viewModel.weekendMinute.collectAsState()
    val receiverMode by viewModel.receiverMode.collectAsState()
    val gracePeriod by viewModel.gracePeriodMinutes.collectAsState()
    val reminderInterval by viewModel.reminderIntervalMinutes.collectAsState()
    val escalationEnabled by viewModel.escalationEnabled.collectAsState()
    val quietHoursEnabled by viewModel.quietHoursEnabled.collectAsState()
    val quietStartHour by viewModel.quietHoursStartHour.collectAsState()
    val quietStartMinute by viewModel.quietHoursStartMinute.collectAsState()
    val quietEndHour by viewModel.quietHoursEndHour.collectAsState()
    val quietEndMinute by viewModel.quietHoursEndMinute.collectAsState()
    val smsEscalation by viewModel.smsEscalationEnabled.collectAsState()
    val moodTracking by viewModel.moodTrackingEnabled.collectAsState()
    val customDayEnabled by viewModel.customDayEnabled.collectAsState()
    val customDayHours by viewModel.customDayHours.collectAsState()
    val customDayMinutes by viewModel.customDayMinutes.collectAsState()

    LaunchedEffect(memberId) {
        viewModel.loadForReceiver(memberId, familyId, receiverId)
    }

    LaunchedEffect(errorMessage) {
        errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    LaunchedEffect(successMessage) {
        successMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearSuccessMessage()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        if (isLoading && settings == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Title
                Text(
                    text = "$receiverName Settings",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )

                // Pause Banner
                AnimatedVisibility(visible = schedulePaused) {
                    Card(
                        shape = MaterialTheme.shapes.medium,
                        colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF7ED))
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Pause, contentDescription = null, tint = Color(0xFFF97316))
                            Spacer(Modifier.width(10.dp))
                            Column {
                                Text("Notifications Paused", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                                Text("Scheduled check-in notifications are paused.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }

                // -- Receiver Mode --
                SettingsSection("Receiver Mode") {
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        ReceiverMode.entries.forEachIndexed { index, mode ->
                            SegmentedButton(
                                selected = receiverMode == mode,
                                onClick = { viewModel.receiverMode.value = mode },
                                shape = SegmentedButtonDefaults.itemShape(index, ReceiverMode.entries.size)
                            ) {
                                Text(mode.displayName)
                            }
                        }
                    }
                    Text(
                        text = "Kid mode provides a fun experience with expanded mood options and location sharing.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // -- Notification Controls --
                SettingsSection("Notification Controls") {
                    SettingsToggle(
                        label = "Pause Notifications",
                        checked = schedulePaused,
                        onCheckedChange = { viewModel.schedulePaused.value = it },
                        description = "Pause scheduled notifications"
                    )

                    OutlinedButton(
                        onClick = { viewModel.sendManualCheckIn() },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isSendingManual
                    ) {
                        if (isSendingManual) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Default.Notifications, contentDescription = null, Modifier.size(18.dp))
                        }
                        Spacer(Modifier.width(8.dp))
                        Text("Send Check-In Now")
                    }
                }

                // -- Schedule Type --
                SettingsSection("Check-In Schedule") {
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        ScheduleType.entries.forEachIndexed { index, type ->
                            SegmentedButton(
                                selected = scheduleType == type,
                                onClick = { viewModel.scheduleType.value = type },
                                shape = SegmentedButtonDefaults.itemShape(index, ScheduleType.entries.size)
                            ) {
                                Text(type.displayName)
                            }
                        }
                    }

                    when (scheduleType) {
                        ScheduleType.Daily -> {
                            TimeRow(
                                label = "Check-In Time",
                                hour = checkinHour,
                                minute = checkinMinute,
                                onHourChange = { viewModel.checkinHour.value = it },
                                onMinuteChange = { viewModel.checkinMinute.value = it }
                            )
                        }
                        ScheduleType.WeekdayWeekend -> {
                            TimeRow(
                                label = "Weekday Time (Mon–Fri)",
                                hour = checkinHour,
                                minute = checkinMinute,
                                onHourChange = { viewModel.checkinHour.value = it },
                                onMinuteChange = { viewModel.checkinMinute.value = it }
                            )
                            TimeRow(
                                label = "Weekend Time (Sat–Sun)",
                                hour = weekendHour,
                                minute = weekendMinute,
                                onHourChange = { viewModel.weekendHour.value = it },
                                onMinuteChange = { viewModel.weekendMinute.value = it }
                            )
                        }
                        ScheduleType.Custom -> {
                            val dayLabels = mapOf(
                                "mon" to "Monday", "tue" to "Tuesday", "wed" to "Wednesday",
                                "thu" to "Thursday", "fri" to "Friday", "sat" to "Saturday", "sun" to "Sunday"
                            )
                            DaySchedule.allDays.forEach { day ->
                                val enabled = customDayEnabled[day] ?: true
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Switch(
                                        checked = enabled,
                                        onCheckedChange = { checked ->
                                            viewModel.customDayEnabled.value = customDayEnabled + (day to checked)
                                        }
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(
                                        text = dayLabels[day] ?: day,
                                        style = MaterialTheme.typography.bodyMedium,
                                        modifier = Modifier.weight(1f)
                                    )
                                    if (enabled) {
                                        Text(
                                            text = formatTime12(customDayHours[day] ?: 8, customDayMinutes[day] ?: 0),
                                            style = MaterialTheme.typography.bodyMedium,
                                            fontWeight = FontWeight.SemiBold,
                                            color = MaterialTheme.colorScheme.primary
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                // -- Timezone --
                settings?.let { s ->
                    SettingsSection("Timezone") {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Timezone", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                text = s.timezone,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                // -- Escalation Chain --
                SettingsSection("Escalation Chain") {
                    SettingsToggle(
                        label = "Escalation Alerts",
                        checked = escalationEnabled,
                        onCheckedChange = { viewModel.escalationEnabled.value = it },
                        description = "Alert if check-in is missed"
                    )

                    AnimatedVisibility(visible = escalationEnabled) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SliderSetting(
                                label = "Grace Period",
                                value = gracePeriod,
                                range = 15..120,
                                step = 15,
                                suffix = "min",
                                onValueChange = { viewModel.gracePeriodMinutes.value = it }
                            )
                            SliderSetting(
                                label = "Reminder Interval",
                                value = reminderInterval,
                                range = 15..120,
                                step = 15,
                                suffix = "min",
                                onValueChange = { viewModel.reminderIntervalMinutes.value = it }
                            )
                        }
                    }
                }

                // -- Quiet Hours --
                SettingsSection("Quiet Hours") {
                    SettingsToggle(
                        label = "Quiet Hours",
                        checked = quietHoursEnabled,
                        onCheckedChange = { viewModel.quietHoursEnabled.value = it },
                        description = "No notifications during specified hours"
                    )

                    AnimatedVisibility(visible = quietHoursEnabled) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            TimeRow(
                                label = "Start",
                                hour = quietStartHour,
                                minute = quietStartMinute,
                                onHourChange = { viewModel.quietHoursStartHour.value = it },
                                onMinuteChange = { viewModel.quietHoursStartMinute.value = it }
                            )
                            TimeRow(
                                label = "End",
                                hour = quietEndHour,
                                minute = quietEndMinute,
                                onHourChange = { viewModel.quietHoursEndHour.value = it },
                                onMinuteChange = { viewModel.quietHoursEndMinute.value = it }
                            )
                        }
                    }
                }

                // -- SMS Escalation --
                SettingsSection("SMS Escalation") {
                    SettingsToggle(
                        label = "SMS Fallback",
                        checked = smsEscalation,
                        onCheckedChange = { viewModel.smsEscalationEnabled.value = it },
                        description = "Send SMS when push notifications fail during escalation"
                    )
                }

                // -- Mood Tracking --
                SettingsSection("Mood Tracking") {
                    SettingsToggle(
                        label = "Mood Tracking",
                        checked = moodTracking,
                        onCheckedChange = { viewModel.moodTrackingEnabled.value = it },
                        description = "Allow sharing mood after check-in"
                    )
                }

                // -- Save Button --
                Button(
                    onClick = { viewModel.saveSettings() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isSaving,
                    shape = MaterialTheme.shapes.large,
                    colors = ButtonDefaults.buttonColors(containerColor = SectionGreen)
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Default.Save, contentDescription = null, Modifier.size(18.dp))
                    }
                    Spacer(Modifier.width(8.dp))
                    Text(if (isSaving) "Saving..." else "Save Settings")
                }

                Spacer(Modifier.height(16.dp))
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }
}

@Composable
private fun SettingsSection(title: String, content: @Composable () -> Unit) {
    Card(
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
            content()
        }
    }
}

@Composable
private fun SettingsToggle(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    description: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = "$label: ${if (checked) "enabled" else "disabled"}" },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun TimeRow(
    label: String,
    hour: Int,
    minute: Int,
    onHourChange: (Int) -> Unit,
    onMinuteChange: (Int) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(
            text = formatTime12(hour, minute),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
    }
}

@Composable
private fun SliderSetting(
    label: String,
    value: Int,
    range: IntRange,
    step: Int,
    suffix: String,
    onValueChange: (Int) -> Unit
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            Text(
                "$value $suffix",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary
            )
        }
        Slider(
            value = value.toFloat(),
            onValueChange = { onValueChange(it.toInt()) },
            valueRange = range.first.toFloat()..range.last.toFloat(),
            steps = (range.last - range.first) / step - 1,
            modifier = Modifier.semantics { contentDescription = "$label: $value $suffix" }
        )
    }
}

private fun formatTime12(hour: Int, minute: Int): String {
    val displayHour = if (hour % 12 == 0) 12 else hour % 12
    val amPm = if (hour < 12) "AM" else "PM"
    return "%d:%02d %s".format(displayHour, minute, amPm)
}
