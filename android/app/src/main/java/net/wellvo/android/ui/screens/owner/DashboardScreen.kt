package net.wellvo.android.ui.screens.owner

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationManagerCompat
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import net.wellvo.android.data.models.KidResponseType
import net.wellvo.android.data.models.LocationLabel
import net.wellvo.android.data.models.Mood
import net.wellvo.android.data.models.WellvoAlert
import net.wellvo.android.data.models.emoji
import net.wellvo.android.data.models.displayName
import net.wellvo.android.viewmodels.DashboardViewModel
import net.wellvo.android.viewmodels.ReceiverCheckInStatus
import net.wellvo.android.viewmodels.ReceiverStatusCard
import net.wellvo.android.viewmodels.WeeklySummary
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

private val StatusGreen = Color(0xFF22C55E)
private val StatusYellow = Color(0xFFF59E0B)
private val StatusRed = Color(0xFFEF4444)
private val StatusGray = Color(0xFF9CA3AF)

private fun ReceiverCheckInStatus.color(): Color = when (this) {
    ReceiverCheckInStatus.CheckedIn -> StatusGreen
    ReceiverCheckInStatus.Pending -> StatusYellow
    ReceiverCheckInStatus.Missed -> StatusRed
    ReceiverCheckInStatus.NoData -> StatusGray
}

private fun ReceiverCheckInStatus.icon(): ImageVector = when (this) {
    ReceiverCheckInStatus.CheckedIn -> Icons.Default.CheckCircle
    ReceiverCheckInStatus.Pending -> Icons.Default.Schedule
    ReceiverCheckInStatus.Missed -> Icons.Default.Cancel
    ReceiverCheckInStatus.NoData -> Icons.Default.RemoveCircle
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    viewModel: DashboardViewModel,
    userId: String,
    modifier: Modifier = Modifier
) {
    val receiverCards by viewModel.receiverCards.collectAsState()
    val weeklySummary by viewModel.weeklySummary.collectAsState()
    val alerts by viewModel.alerts.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(userId) {
        viewModel.loadDashboard(userId)
    }

    LaunchedEffect(errorMessage) {
        errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = isLoading,
            onRefresh = { viewModel.loadDashboard(userId) },
            modifier = Modifier.fillMaxSize()
        ) {
            when {
                isLoading && receiverCards.isEmpty -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = StatusGreen)
                            Spacer(modifier = Modifier.height(16.dp))
                            Text("Loading...", style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }

                receiverCards.isEmpty && !isLoading -> {
                    EmptyState()
                }

                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        // Notification permission banner
                        item { NotificationPermissionBanner() }

                        // Pattern Alerts
                        if (alerts.isNotEmpty()) {
                            item {
                                AlertsBanner(
                                    alerts = alerts,
                                    onDismiss = { viewModel.dismissAlert(it) }
                                )
                            }
                        }

                        // Weekly Summary
                        weeklySummary?.let { summary ->
                            item { WeeklySummaryCard(summary = summary) }
                        }

                        // Today's Timeline
                        if (receiverCards.isNotEmpty()) {
                            item { TodayTimelineCard(cards = receiverCards) }
                        }

                        // Receiver Status Cards
                        items(receiverCards, key = { it.id }) { card ->
                            ReceiverStatusCardView(
                                card = card,
                                onCheckOn = { viewModel.sendOnDemandCheckIn(card.id) }
                            )
                        }

                        item { Spacer(modifier = Modifier.height(8.dp)) }
                    }
                }
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }
}

@Composable
private fun EmptyState() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.PersonAdd,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(20.dp))
        Text(
            text = "No Receivers Yet",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Add a family member to start receiving daily check-ins.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

// -- Weekly Summary Card --

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WeeklySummaryCard(summary: WeeklySummary) {
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "This Week",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                val consistencyColor = when {
                    summary.consistencyPercentage >= 80 -> StatusGreen
                    summary.consistencyPercentage >= 50 -> StatusYellow
                    else -> StatusRed
                }
                StatBubble(
                    value = "${summary.consistencyPercentage.toInt()}%",
                    label = "Consistency",
                    color = consistencyColor,
                    modifier = Modifier.weight(1f)
                )
                StatBubble(
                    value = summary.averageCheckInTime,
                    label = "Avg Time",
                    color = Color(0xFF3B82F6),
                    modifier = Modifier.weight(1f)
                )
                StatBubble(
                    value = "${summary.totalCheckIns}/${summary.totalExpected}",
                    label = "Check-Ins",
                    color = StatusGreen,
                    modifier = Modifier.weight(1f)
                )
            }

            if (summary.moodBreakdown.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = "Moods:",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    summary.moodBreakdown.forEach { (mood, count) ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.semantics {
                                contentDescription = "${mood.displayName()}: $count"
                            }
                        ) {
                            Text(text = mood.emoji(), style = MaterialTheme.typography.bodyMedium)
                            Spacer(modifier = Modifier.width(2.dp))
                            Text(
                                text = "$count",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatBubble(
    value: String,
    label: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.semantics { contentDescription = "$label: $value" },
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = color
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

// -- Today's Timeline Card --

@Composable
private fun TodayTimelineCard(cards: List<ReceiverStatusCard>) {
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Today's Timeline",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(12.dp))

            cards.forEach { card ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 6.dp)
                        .semantics {
                            contentDescription = "${card.name}: ${
                                if (card.checkedInTime != null) "checked in at ${formatTimeShort(card.checkedInTime)}"
                                else card.status.label
                            }"
                        },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Status dot
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(card.status.color())
                    )
                    Spacer(modifier = Modifier.width(12.dp))

                    Text(
                        text = card.name,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f)
                    )

                    // Status icon + time/label
                    Icon(
                        imageVector = card.status.icon(),
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = card.status.color()
                    )
                    Spacer(modifier = Modifier.width(4.dp))

                    val timeText = card.checkedInTime?.let { formatTimeShort(it) }
                    Text(
                        text = timeText ?: card.status.label,
                        style = MaterialTheme.typography.labelSmall,
                        color = if (timeText != null) MaterialTheme.colorScheme.onSurfaceVariant
                                else card.status.color()
                    )

                    // Timeline bar
                    Spacer(modifier = Modifier.width(8.dp))
                    TimelineBar(
                        checkedInTime = card.checkedInTime,
                        statusColor = card.status.color()
                    )
                }
            }
        }
    }
}

@Composable
private fun TimelineBar(checkedInTime: String?, statusColor: Color) {
    Box(
        modifier = Modifier
            .width(60.dp)
            .height(4.dp)
            .clip(RoundedCornerShape(2.dp))
            .background(MaterialTheme.colorScheme.outlineVariant)
    ) {
        if (checkedInTime != null) {
            val progress = parseTimeProgress(checkedInTime)
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction = progress.coerceIn(0.02f, 1f))
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(statusColor)
            )
        }
    }
}

// -- Alerts Banner --

@Composable
private fun AlertsBanner(alerts: List<WellvoAlert>, onDismiss: (WellvoAlert) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        alerts.forEach { alert ->
            Card(
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(
                    containerColor = Color(0xFFFFF7ED)
                )
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    Icon(
                        imageVector = if (alert.type == "time_drift") Icons.Default.Schedule
                                      else Icons.Default.Warning,
                        contentDescription = null,
                        tint = Color(0xFFF97316),
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))

                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = alert.title,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = alert.message,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        val driftHours = alert.data?.get("drift_hours")
                        if (driftHours != null) {
                            Text(
                                text = "Shifted by ${"%.1f".format(driftHours)} hours",
                                style = MaterialTheme.typography.labelSmall,
                                color = Color(0xFFF97316)
                            )
                        }
                    }

                    IconButton(onClick = { onDismiss(alert) }) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Dismiss alert",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

// -- Receiver Status Card --

@Composable
private fun ReceiverStatusCardView(
    card: ReceiverStatusCard,
    onCheckOn: () -> Unit
) {
    Card(
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .shadow(
                elevation = 2.dp,
                shape = RoundedCornerShape(16.dp),
                ambientColor = Color.Black.copy(alpha = 0.05f)
            )
            .semantics {
                contentDescription = "${card.name}, ${card.status.label}, ${card.streak} day streak"
            },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header: Avatar + Name/Status + Streak
            Row(verticalAlignment = Alignment.CenterVertically) {
                // Avatar with status icon
                Box(
                    modifier = Modifier
                        .size(50.dp)
                        .clip(CircleShape)
                        .background(card.status.color().copy(alpha = 0.2f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = card.status.icon(),
                        contentDescription = null,
                        tint = card.status.color(),
                        modifier = Modifier.size(28.dp)
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = card.name,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold
                        )
                        if (!card.hasNotificationsEnabled) {
                            Spacer(modifier = Modifier.width(6.dp))
                            Icon(
                                imageVector = Icons.Default.NotificationsOff,
                                contentDescription = "Notifications not enabled",
                                modifier = Modifier.size(14.dp),
                                tint = Color(0xFFF97316)
                            )
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = card.status.icon(),
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = card.status.color()
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = card.status.label,
                            style = MaterialTheme.typography.bodySmall,
                            color = card.status.color()
                        )
                    }
                }

                // Streak
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "${card.streak}",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = StatusGreen
                    )
                    Text(
                        text = "day streak",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Notification warning
            AnimatedVisibility(visible = !card.hasNotificationsEnabled) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp)
                        .background(
                            Color(0xFFF97316).copy(alpha = 0.1f),
                            RoundedCornerShape(8.dp)
                        )
                        .padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Warning,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = Color(0xFFF97316)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "${card.name} hasn't enabled notifications. They may miss check-in reminders.",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFFF97316)
                    )
                }
            }

            // Last check-in time
            card.lastCheckIn?.let { lastCheckIn ->
                Spacer(modifier = Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.AccessTime,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Last check-in: ${formatTimestamp(lastCheckIn)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Mood indicator
            card.mood?.let { mood ->
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.semantics {
                        contentDescription = "Mood: ${mood.displayName()}"
                    }
                ) {
                    Text(
                        text = "Mood:",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(text = mood.emoji(), style = MaterialTheme.typography.bodyMedium)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = mood.displayName(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Location label (kid mode)
            card.locationLabel?.takeIf { it.isNotEmpty() }?.let { label ->
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.semantics {
                        contentDescription = "Location: ${locationLabelDisplay(label)}"
                    }
                ) {
                    Icon(
                        imageVector = Icons.Default.LocationOn,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = Color(0xFF3B82F6)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "At: ${locationLabelDisplay(label)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Kid response type badge
            card.kidResponseType?.takeIf { it.isNotEmpty() }?.let { response ->
                Spacer(modifier = Modifier.height(8.dp))
                KidResponseBadge(rawValue = response)
            }

            // Check on button
            if (card.status != ReceiverCheckInStatus.CheckedIn) {
                Spacer(modifier = Modifier.height(12.dp))
                Button(
                    onClick = onCheckOn,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFF97316)
                    ),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.NotificationsOff,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Check on ${card.name}")
                }
            }
        }
    }
}

@Composable
private fun KidResponseBadge(rawValue: String) {
    val responseType = KidResponseType.fromSerialName(rawValue)
    val text = responseType?.label ?: rawValue
    val bgColor = responseType?.color ?: StatusGray
    val icon = when (responseType) {
        KidResponseType.Sos -> Icons.Default.Warning
        else -> Icons.Default.HourglassEmpty
    }

    Row(
        modifier = Modifier
            .background(bgColor, RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .semantics { contentDescription = "Kid response: $text" },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(12.dp),
            tint = Color.White
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            color = Color.White
        )
    }
}

// -- Notification Permission Banner --

@Composable
private fun NotificationPermissionBanner() {
    val context = LocalContext.current
    val notificationsEnabled = remember {
        mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled())
    }

    LaunchedEffect(Unit) {
        notificationsEnabled.value = NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    AnimatedVisibility(visible = !notificationsEnabled.value) {
        Card(
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(
                containerColor = Color(0xFFFFF7ED)
            )
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Notifications,
                    contentDescription = null,
                    tint = Color(0xFFF97316),
                    modifier = Modifier.size(24.dp)
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Notifications Disabled",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Enable notifications to receive check-in alerts.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                OutlinedButton(
                    onClick = {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        }
                        context.startActivity(intent)
                    }
                ) {
                    Text("Enable", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

// -- Utility Functions --

private fun locationLabelDisplay(rawValue: String): String {
    return LocationLabel.fromSerialName(rawValue)?.displayName
        ?: rawValue.replace("_", " ").replaceFirstChar { it.uppercase() }
}

private fun formatTimestamp(timestamp: String): String {
    return try {
        val dt = LocalDateTime.parse(
            timestamp.replace("Z", "").substringBefore("+"),
            DateTimeFormatter.ISO_LOCAL_DATE_TIME
        )
        dt.format(DateTimeFormatter.ofPattern("MMM d, h:mm a"))
    } catch (_: DateTimeParseException) {
        timestamp
    }
}

private fun formatTimeShort(timestamp: String): String {
    return try {
        val dt = LocalDateTime.parse(
            timestamp.replace("Z", "").substringBefore("+"),
            DateTimeFormatter.ISO_LOCAL_DATE_TIME
        )
        dt.format(DateTimeFormatter.ofPattern("h:mm a"))
    } catch (_: DateTimeParseException) {
        timestamp
    }
}

private fun parseTimeProgress(timestamp: String): Float {
    return try {
        val dt = LocalDateTime.parse(
            timestamp.replace("Z", "").substringBefore("+"),
            DateTimeFormatter.ISO_LOCAL_DATE_TIME
        )
        (dt.hour * 60 + dt.minute).toFloat() / (24 * 60).toFloat()
    } catch (_: DateTimeParseException) {
        0f
    }
}
