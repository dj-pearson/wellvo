package net.wellvo.android.ui.screens.owner

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import net.wellvo.android.data.models.CheckIn
import net.wellvo.android.data.models.CheckInSource
import net.wellvo.android.data.models.CheckInResponseType
import net.wellvo.android.data.models.emoji
import net.wellvo.android.data.models.displayName
import net.wellvo.android.viewmodels.HistoryViewModel
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

private val periods = listOf(7, 30, 90)
private val periodLabels = mapOf(7 to "7 Days", 30 to "30 Days", 90 to "90 Days")

private val SourceApp = Color(0xFF22C55E)
private val SourceNotification = Color(0xFF3B82F6)
private val SourceOnDemand = Color(0xFFF97316)
private val SourceNeedHelp = Color(0xFFEF4444)

@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel,
    userId: String,
    modifier: Modifier = Modifier
) {
    val receivers by viewModel.receivers.collectAsState()
    val selectedReceiverId by viewModel.selectedReceiverId.collectAsState()
    val selectedPeriod by viewModel.selectedPeriod.collectAsState()
    val checkIns by viewModel.checkIns.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isExporting by viewModel.isExporting.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val haptic = LocalHapticFeedback.current
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    LaunchedEffect(userId) {
        viewModel.initialize(userId)
    }

    LaunchedEffect(errorMessage) {
        errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Period selector chips + export button
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        periods.forEach { period ->
                            FilterChip(
                                selected = selectedPeriod == period,
                                onClick = { viewModel.selectPeriod(period) },
                                label = { Text(periodLabels[period] ?: "$period Days") }
                            )
                        }
                    }
                    if (checkIns.isNotEmpty()) {
                        IconButton(
                            onClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                viewModel.exportPdf(context) { intent ->
                                    context.startActivity(intent)
                                }
                            },
                            enabled = !isExporting
                        ) {
                            if (isExporting) {
                                CircularProgressIndicator(modifier = Modifier.size(24.dp))
                            } else {
                                Icon(
                                    imageVector = Icons.Default.Share,
                                    contentDescription = "Export PDF"
                                )
                            }
                        }
                    }
                }
            }

            // Receiver selector chips
            if (receivers.size > 1) {
                item {
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        receivers.forEach { receiver ->
                            FilterChip(
                                selected = selectedReceiverId == receiver.id,
                                onClick = { viewModel.selectReceiver(receiver.id) },
                                label = { Text(receiver.name) }
                            )
                        }
                    }
                }
            }

            if (isLoading && checkIns.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
            } else if (checkIns.isEmpty()) {
                item {
                    EmptyHistoryState()
                }
            } else {
                // Calendar heatmap above log entries
                item {
                    CalendarHeatmap(
                        checkIns = checkIns,
                        days = selectedPeriod
                    )
                }

                // Trend chart between heatmap and log
                item {
                    TrendChart(
                        checkIns = checkIns,
                        days = selectedPeriod
                    )
                }

                items(checkIns, key = { it.id }) { checkIn ->
                    CheckInLogEntry(checkIn = checkIn)
                }
            }

            item { Spacer(Modifier.height(8.dp)) }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }
}

@Composable
private fun CheckInLogEntry(checkIn: CheckIn) {
    val (dateStr, timeStr) = formatCheckInDateTime(checkIn.checkedInAt)
    val moodEmoji = checkIn.mood?.emoji() ?: ""
    val moodName = checkIn.mood?.displayName() ?: ""
    val sourceBadge = sourceLabel(checkIn.source)
    val sourceColor = sourceColor(checkIn.source)

    Card(
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.semantics {
            contentDescription = "$dateStr at $timeStr${if (moodName.isNotEmpty()) ", mood: $moodName" else ""}, source: $sourceBadge"
        }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Date/Time
            Column {
                Text(
                    text = dateStr,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = timeStr,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(Modifier.width(12.dp))

            // Mood
            if (moodEmoji.isNotEmpty()) {
                Text(text = moodEmoji, style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.width(8.dp))
            }

            Spacer(Modifier.weight(1f))

            // Source badge
            Text(
                text = sourceBadge,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                color = Color.White,
                modifier = Modifier
                    .background(sourceColor, RoundedCornerShape(50))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            )

            // Response type badge
            checkIn.responseType?.let { type ->
                Spacer(Modifier.width(6.dp))
                val rtLabel = when (type) {
                    CheckInResponseType.Ok -> "OK"
                    CheckInResponseType.NeedHelp -> "Need Help"
                    CheckInResponseType.CallMe -> "Call Me"
                }
                val rtColor = when (type) {
                    CheckInResponseType.Ok -> SourceApp
                    CheckInResponseType.NeedHelp -> SourceNeedHelp
                    CheckInResponseType.CallMe -> SourceOnDemand
                }
                Text(
                    text = rtLabel,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Medium,
                    color = Color.White,
                    modifier = Modifier
                        .background(rtColor, RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                )
            }
        }
    }
}

@Composable
private fun EmptyHistoryState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(48.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Default.DateRange,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(16.dp))
        Text(
            text = "No check-ins for this period.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

private fun sourceLabel(source: CheckInSource): String = when (source) {
    CheckInSource.App -> "App"
    CheckInSource.Notification -> "Notification"
    CheckInSource.OnDemand -> "On Demand"
    CheckInSource.NeedHelp -> "Need Help"
    CheckInSource.CallMe -> "Call Me"
}

private fun sourceColor(source: CheckInSource): Color = when (source) {
    CheckInSource.App -> SourceApp
    CheckInSource.Notification -> SourceNotification
    CheckInSource.OnDemand -> SourceOnDemand
    CheckInSource.NeedHelp -> SourceNeedHelp
    CheckInSource.CallMe -> SourceNeedHelp
}

private fun formatCheckInDateTime(timestamp: String): Pair<String, String> {
    return try {
        val dt = LocalDateTime.parse(
            timestamp.replace("Z", "").substringBefore("+"),
            DateTimeFormatter.ISO_LOCAL_DATE_TIME
        )
        val date = dt.format(DateTimeFormatter.ofPattern("MMM d, yyyy"))
        val time = dt.format(DateTimeFormatter.ofPattern("h:mm a"))
        date to time
    } catch (_: DateTimeParseException) {
        timestamp to ""
    }
}
