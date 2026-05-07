package net.dailyok.android.ui.screens.owner

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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import net.dailyok.android.R
import net.dailyok.android.ui.theme.DailyOKSpacing
import net.dailyok.android.data.models.CheckIn
import net.dailyok.android.data.models.CheckInSource
import net.dailyok.android.data.models.CheckInResponseType
import net.dailyok.android.data.models.emoji
import net.dailyok.android.data.models.displayName
import net.dailyok.android.viewmodels.HistoryViewModel
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

private val periods = listOf(7, 30, 90)

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
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    val hasMorePages by viewModel.hasMorePages.collectAsState()
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
        net.dailyok.android.ui.components.AmbientBackground(
            tone = net.dailyok.android.ui.components.AmbientTone.Neutral
        )
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(DailyOKSpacing.md),
            verticalArrangement = Arrangement.spacedBy(DailyOKSpacing.sm)
        ) {
            // Period selector chips + export button
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(DailyOKSpacing.xs)
                    ) {
                        periods.forEach { period ->
                            val periodLabel = when (period) {
                                7 -> stringResource(R.string.history_7_days)
                                30 -> stringResource(R.string.history_30_days)
                                90 -> stringResource(R.string.history_90_days)
                                else -> "$period Days"
                            }
                            FilterChip(
                                selected = selectedPeriod == period,
                                onClick = { viewModel.selectPeriod(period) },
                                label = { Text(periodLabel) }
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
                                    contentDescription = stringResource(R.string.history_export_pdf)
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
                        horizontalArrangement = Arrangement.spacedBy(DailyOKSpacing.xs)
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
                    net.dailyok.android.ui.components.HistorySkeletonView()
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

                // Load more trigger
                if (hasMorePages) {
                    item {
                        LaunchedEffect(Unit) {
                            viewModel.loadMore()
                        }
                        if (isLoadingMore) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator(modifier = Modifier.size(24.dp))
                            }
                        }
                    }
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
                .padding(DailyOKSpacing.sm),
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

            Spacer(Modifier.width(DailyOKSpacing.sm))

            // Mood
            if (moodEmoji.isNotEmpty()) {
                Text(text = moodEmoji, style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.width(DailyOKSpacing.xs))
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
                    CheckInResponseType.Ok -> stringResource(R.string.history_response_ok)
                    CheckInResponseType.NeedHelp -> stringResource(R.string.history_source_need_help)
                    CheckInResponseType.CallMe -> stringResource(R.string.history_source_call_me)
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
    net.dailyok.android.ui.components.EmptyStateView(
        icon = Icons.Default.DateRange,
        title = stringResource(R.string.history_no_checkins),
        body = "Once your family starts checking in, their history will show up here."
    )
}

@Composable
private fun sourceLabel(source: CheckInSource): String = when (source) {
    CheckInSource.App -> stringResource(R.string.history_source_app)
    CheckInSource.Notification -> stringResource(R.string.history_source_notification)
    CheckInSource.OnDemand -> stringResource(R.string.history_source_on_demand)
    CheckInSource.NeedHelp -> stringResource(R.string.history_source_need_help)
    CheckInSource.CallMe -> stringResource(R.string.history_source_call_me)
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
