package net.wellvo.android.ui.screens.owner

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import net.wellvo.android.data.models.CheckIn
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit

private val ChartLine = Color(0xFF3B82F6)
private val ChartDot = Color(0xFF2563EB)
private val ChartGrid = Color(0xFFE5E7EB)
private val ChartLabel = 0xFF9CA3AF.toInt()

private const val CHART_HEIGHT_DP = 180f
private const val LEFT_PADDING = 50f
private const val RIGHT_PADDING = 16f
private const val TOP_PADDING = 12f
private const val BOTTOM_PADDING = 28f

data class TrendDataPoint(
    val label: String,
    val avgMinutes: Int, // minutes since midnight
    val date: LocalDate
)

@Composable
fun TrendChart(
    checkIns: List<CheckIn>,
    days: Int,
    modifier: Modifier = Modifier
) {
    val dataPoints = buildTrendData(checkIns, days)
    val stats = computeStats(checkIns)

    Card(
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = "Check-in Time Trend",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(8.dp))

            if (dataPoints.isEmpty()) {
                Text(
                    text = "Not enough data to show trend.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                val minTime = (dataPoints.minOf { it.avgMinutes } / 60) * 60 // Round down to hour
                val maxTime = ((dataPoints.maxOf { it.avgMinutes } / 60) + 1) * 60 // Round up
                val timeRange = (maxTime - minTime).coerceAtLeast(60) // At least 1 hour range

                val chartWidthDp = (LEFT_PADDING + RIGHT_PADDING + dataPoints.size * 48f).coerceAtLeast(300f)

                Row(modifier = Modifier.horizontalScroll(rememberScrollState())) {
                    Canvas(
                        modifier = Modifier
                            .width(chartWidthDp.dp)
                            .height(CHART_HEIGHT_DP.dp)
                            .semantics {
                                contentDescription = "Check-in time trend chart. ${stats.summary}"
                            }
                    ) {
                        val chartLeft = LEFT_PADDING * density
                        val chartRight = size.width - RIGHT_PADDING * density
                        val chartTop = TOP_PADDING * density
                        val chartBottom = size.height - BOTTOM_PADDING * density
                        val chartWidth = chartRight - chartLeft
                        val chartHeight = chartBottom - chartTop

                        // Draw horizontal grid lines and Y-axis labels (hours)
                        val hourStart = minTime / 60
                        val hourEnd = maxTime / 60
                        for (hour in hourStart..hourEnd) {
                            val minutes = hour * 60
                            val y = chartBottom - ((minutes - minTime).toFloat() / timeRange) * chartHeight
                            // Grid line
                            drawLine(
                                color = ChartGrid,
                                start = Offset(chartLeft, y),
                                end = Offset(chartRight, y),
                                strokeWidth = 1f
                            )
                            // Label
                            val label = formatHourLabel(hour)
                            drawContext.canvas.nativeCanvas.drawText(
                                label,
                                4f * density,
                                y + 4f * density,
                                android.graphics.Paint().apply {
                                    textSize = 10f * density
                                    color = ChartLabel
                                    isAntiAlias = true
                                }
                            )
                        }

                        if (dataPoints.size == 1) {
                            // Single point: just draw the dot
                            val x = chartLeft + chartWidth / 2f
                            val y = chartBottom - ((dataPoints[0].avgMinutes - minTime).toFloat() / timeRange) * chartHeight
                            drawCircle(ChartDot, radius = 5f * density, center = Offset(x, y))
                            // X label
                            drawContext.canvas.nativeCanvas.drawText(
                                dataPoints[0].label,
                                x,
                                chartBottom + 16f * density,
                                android.graphics.Paint().apply {
                                    textSize = 9f * density
                                    color = ChartLabel
                                    isAntiAlias = true
                                    textAlign = android.graphics.Paint.Align.CENTER
                                }
                            )
                        } else {
                            // Draw line and dots
                            val stepX = chartWidth / (dataPoints.size - 1).coerceAtLeast(1)
                            val points = dataPoints.mapIndexed { i, dp ->
                                val x = chartLeft + i * stepX
                                val y = chartBottom - ((dp.avgMinutes - minTime).toFloat() / timeRange) * chartHeight
                                Offset(x, y)
                            }

                            // Draw line path
                            val path = Path()
                            points.forEachIndexed { i, pt ->
                                if (i == 0) path.moveTo(pt.x, pt.y)
                                else path.lineTo(pt.x, pt.y)
                            }
                            drawPath(path, ChartLine, style = Stroke(width = 2.5f * density, cap = StrokeCap.Round))

                            // Draw dots
                            for (pt in points) {
                                drawCircle(Color.White, radius = 4.5f * density, center = pt)
                                drawCircle(ChartDot, radius = 3f * density, center = pt)
                            }

                            // X-axis labels
                            val labelPaint = android.graphics.Paint().apply {
                                textSize = 9f * density
                                color = ChartLabel
                                isAntiAlias = true
                                textAlign = android.graphics.Paint.Align.CENTER
                            }
                            // Show subset of labels to avoid overlap
                            val labelInterval = when {
                                dataPoints.size <= 7 -> 1
                                dataPoints.size <= 14 -> 2
                                else -> 3
                            }
                            for (i in dataPoints.indices step labelInterval) {
                                drawContext.canvas.nativeCanvas.drawText(
                                    dataPoints[i].label,
                                    points[i].x,
                                    chartBottom + 16f * density,
                                    labelPaint
                                )
                            }
                        }
                    }
                }
            }

            // Summary stats
            if (stats.avgTime.isNotEmpty()) {
                Spacer(Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    StatItem("Average", stats.avgTime)
                    StatItem("Earliest", stats.earliest)
                    StatItem("Latest", stats.latest)
                }
            }
        }
    }
}

@Composable
private fun StatItem(label: String, value: String) {
    Column(horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private data class TrendStats(
    val avgTime: String,
    val earliest: String,
    val latest: String,
    val summary: String
)

private fun computeStats(checkIns: List<CheckIn>): TrendStats {
    val minutes = checkIns.mapNotNull { ci ->
        try {
            val dt = LocalDateTime.parse(
                ci.checkedInAt.replace("Z", "").substringBefore("+"),
                DateTimeFormatter.ISO_LOCAL_DATE_TIME
            )
            dt.hour * 60 + dt.minute
        } catch (_: DateTimeParseException) { null }
    }
    if (minutes.isEmpty()) return TrendStats("", "", "", "No check-in data")
    val avg = minutes.average().toInt()
    val min = minutes.min()
    val max = minutes.max()
    return TrendStats(
        avgTime = formatMinutes(avg),
        earliest = formatMinutes(min),
        latest = formatMinutes(max),
        summary = "Average: ${formatMinutes(avg)}, Earliest: ${formatMinutes(min)}, Latest: ${formatMinutes(max)}"
    )
}

private fun buildTrendData(checkIns: List<CheckIn>, days: Int): List<TrendDataPoint> {
    if (checkIns.isEmpty()) return emptyList()

    // Parse check-in times by date
    val byDate = mutableMapOf<LocalDate, MutableList<Int>>()
    for (ci in checkIns) {
        try {
            val dt = LocalDateTime.parse(
                ci.checkedInAt.replace("Z", "").substringBefore("+"),
                DateTimeFormatter.ISO_LOCAL_DATE_TIME
            )
            val date = dt.toLocalDate()
            val mins = dt.hour * 60 + dt.minute
            byDate.getOrPut(date) { mutableListOf() }.add(mins)
        } catch (_: DateTimeParseException) { /* skip */ }
    }

    return if (days <= 7) {
        // Daily points
        val today = LocalDate.now()
        val start = today.minusDays(days.toLong())
        val formatter = DateTimeFormatter.ofPattern("M/d")
        (0..days).mapNotNull { offset ->
            val date = start.plusDays(offset.toLong())
            val times = byDate[date] ?: return@mapNotNull null
            TrendDataPoint(
                label = date.format(formatter),
                avgMinutes = times.average().toInt(),
                date = date
            )
        }
    } else {
        // Weekly buckets
        val today = LocalDate.now()
        val start = today.minusDays(days.toLong())
        val weeks = mutableListOf<TrendDataPoint>()
        var weekStart = start
        val formatter = DateTimeFormatter.ofPattern("M/d")
        while (weekStart <= today) {
            val weekEnd = weekStart.plusDays(6).let { if (it > today) today else it }
            val weekMinutes = mutableListOf<Int>()
            var d = weekStart
            while (d <= weekEnd) {
                byDate[d]?.let { weekMinutes.addAll(it) }
                d = d.plusDays(1)
            }
            if (weekMinutes.isNotEmpty()) {
                weeks.add(
                    TrendDataPoint(
                        label = weekStart.format(formatter),
                        avgMinutes = weekMinutes.average().toInt(),
                        date = weekStart
                    )
                )
            }
            weekStart = weekStart.plusDays(7)
        }
        weeks
    }
}

private fun formatMinutes(minutes: Int): String {
    val h = minutes / 60
    val m = minutes % 60
    val amPm = if (h < 12) "AM" else "PM"
    val h12 = if (h % 12 == 0) 12 else h % 12
    return "%d:%02d %s".format(h12, m, amPm)
}

private fun formatHourLabel(hour: Int): String {
    val h = hour % 24
    val amPm = if (h < 12) "AM" else "PM"
    val h12 = if (h % 12 == 0) 12 else h % 12
    return "$h12 $amPm"
}
