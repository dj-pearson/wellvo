package net.wellvo.android.ui.screens.owner

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
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

private val HeatmapOnTime = Color(0xFF22C55E)
private val HeatmapLate = Color(0xFFF59E0B)
private val HeatmapMissed = Color(0xFFEF4444)
private val HeatmapNoData = Color(0xFFE5E7EB)
private val HeatmapFuture = Color(0xFFF3F4F6)
private val HeatmapSymbolColor = Color(0xE6FFFFFF)

private const val CELL_SIZE = 14f
private const val CELL_SPACING = 3f
private const val CELL_RADIUS = 2f
private const val LEFT_LABEL_WIDTH = 20f

private enum class CellStatus(val color: Color, val symbol: String, val label: String) {
    ON_TIME(HeatmapOnTime, "\u2713", "On time"),
    LATE(HeatmapLate, "!", "Late"),
    MISSED(HeatmapMissed, "\u2715", "Missed"),
    NO_DATA(HeatmapNoData, "", "No data"),
    FUTURE(HeatmapFuture, "", "Future")
}

@Composable
fun CalendarHeatmap(
    checkIns: List<CheckIn>,
    days: Int,
    modifier: Modifier = Modifier
) {
    val today = LocalDate.now()
    val startDate = today.minusDays(days.toLong())

    // Build lookup: date -> CheckIn
    val checkInMap = buildCheckInMap(checkIns)

    // Build grid data: weeks as columns, days as rows (Mon=0 to Sun=6)
    val gridData = buildGridData(startDate, today, checkInMap)
    val numWeeks = gridData.size

    // Build accessibility description
    val accessibilityDesc = buildAccessibilityDescription(gridData)

    Card(
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = "Check-in Calendar",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(8.dp))

            // Scrollable grid
            val totalWidth = LEFT_LABEL_WIDTH + numWeeks * (CELL_SIZE + CELL_SPACING)
            val totalHeight = 7 * (CELL_SIZE + CELL_SPACING)

            Row(
                modifier = Modifier
                    .horizontalScroll(rememberScrollState())
                    .semantics { contentDescription = accessibilityDesc }
            ) {
                Canvas(
                    modifier = Modifier
                        .width((totalWidth / 1f).dp)
                        .height((totalHeight / 1f).dp)
                ) {
                    // Draw day-of-week labels (M, W, F)
                    val dayLabels = listOf("M" to 0, "W" to 2, "F" to 4)
                    for ((label, row) in dayLabels) {
                        val y = row * (CELL_SIZE + CELL_SPACING) + CELL_SIZE / 2f + 4f
                        drawContext.canvas.nativeCanvas.drawText(
                            label,
                            0f,
                            y * density,
                            android.graphics.Paint().apply {
                                textSize = 9f * density
                                color = 0xFF9CA3AF.toInt()
                                isAntiAlias = true
                            }
                        )
                    }

                    // Draw cells
                    for ((weekIdx, week) in gridData.withIndex()) {
                        for ((dayIdx, cell) in week.withIndex()) {
                            if (cell == null) continue
                            val x = LEFT_LABEL_WIDTH + weekIdx * (CELL_SIZE + CELL_SPACING)
                            val y = dayIdx * (CELL_SIZE + CELL_SPACING)
                            drawCell(x, y, cell.status)
                        }
                    }
                }
            }

            Spacer(Modifier.height(10.dp))

            // Legend
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                LegendItem(color = HeatmapOnTime, symbol = "\u2713", label = "On time")
                LegendItem(color = HeatmapLate, symbol = "!", label = "Late")
                LegendItem(color = HeatmapMissed, symbol = "\u2715", label = "Missed")
                LegendItem(color = HeatmapNoData, symbol = "", label = "No data")
            }
        }
    }
}

private fun DrawScope.drawCell(x: Float, y: Float, status: CellStatus) {
    val xPx = x * density
    val yPx = y * density
    val sizePx = CELL_SIZE * density
    val radiusPx = CELL_RADIUS * density

    // Draw rounded rect
    drawRoundRect(
        color = status.color,
        topLeft = Offset(xPx, yPx),
        size = Size(sizePx, sizePx),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(radiusPx, radiusPx)
    )

    // Draw symbol
    if (status.symbol.isNotEmpty()) {
        drawContext.canvas.nativeCanvas.drawText(
            status.symbol,
            xPx + sizePx / 2f - 3f * density,
            yPx + sizePx / 2f + 3.5f * density,
            android.graphics.Paint().apply {
                textSize = 8f * density
                color = 0xE6FFFFFF.toInt()
                isAntiAlias = true
                isFakeBoldText = true
                textAlign = android.graphics.Paint.Align.CENTER
                this.textAlign = android.graphics.Paint.Align.CENTER
            }
        )
    }
}

@Composable
private fun LegendItem(color: Color, symbol: String, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(modifier = Modifier.size(10.dp)) {
            Canvas(modifier = Modifier.size(10.dp)) {
                drawRoundRect(
                    color = color,
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(2f, 2f)
                )
            }
        }
        Spacer(Modifier.width(4.dp))
        Text(
            text = if (symbol.isNotEmpty()) "$symbol $label" else label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private data class CellData(
    val date: LocalDate,
    val status: CellStatus
)

private fun buildCheckInMap(checkIns: List<CheckIn>): Map<LocalDate, CheckIn> {
    val map = mutableMapOf<LocalDate, CheckIn>()
    for (ci in checkIns) {
        try {
            val dt = LocalDateTime.parse(
                ci.checkedInAt.replace("Z", "").substringBefore("+"),
                DateTimeFormatter.ISO_LOCAL_DATE_TIME
            )
            val date = dt.toLocalDate()
            // Keep first check-in per day (the one that counts)
            if (!map.containsKey(date)) {
                map[date] = ci
            }
        } catch (_: DateTimeParseException) {
            // Skip unparseable entries
        }
    }
    return map
}

private fun buildGridData(
    startDate: LocalDate,
    today: LocalDate,
    checkInMap: Map<LocalDate, CheckIn>
): List<List<CellData?>> {
    val weeks = mutableListOf<MutableList<CellData?>>()

    var current = startDate
    // Pad to start of the week (Monday)
    val startDayOfWeek = current.dayOfWeek.value - 1 // Monday=0
    val weekStart = current.minusDays(startDayOfWeek.toLong())
    current = weekStart

    var currentWeek = mutableListOf<CellData?>()
    while (current <= today || currentWeek.size % 7 != 0) {
        val dayIdx = current.dayOfWeek.value - 1 // Monday=0

        if (dayIdx == 0 && currentWeek.isNotEmpty()) {
            weeks.add(currentWeek)
            currentWeek = mutableListOf()
        }

        val status = when {
            current > today -> CellStatus.FUTURE
            current < startDate -> CellStatus.NO_DATA
            else -> {
                val checkIn = checkInMap[current]
                if (checkIn != null) {
                    if (isLate(checkIn)) CellStatus.LATE else CellStatus.ON_TIME
                } else {
                    if (current < today) CellStatus.MISSED else CellStatus.NO_DATA
                }
            }
        }

        currentWeek.add(CellData(current, status))
        current = current.plusDays(1)

        // Safety: stop if we've gone more than a week past today
        if (current > today.plusDays(7)) break
    }
    if (currentWeek.isNotEmpty()) {
        // Pad remainder of last week
        while (currentWeek.size < 7) {
            currentWeek.add(CellData(current, CellStatus.FUTURE))
            current = current.plusDays(1)
        }
        weeks.add(currentWeek)
    }

    return weeks
}

private fun isLate(checkIn: CheckIn): Boolean {
    val scheduledTime = checkIn.scheduledFor ?: return false
    try {
        val checkedInDt = LocalDateTime.parse(
            checkIn.checkedInAt.replace("Z", "").substringBefore("+"),
            DateTimeFormatter.ISO_LOCAL_DATE_TIME
        )
        // scheduledFor might be a full datetime or just time
        val scheduledMinutes = if (scheduledTime.contains("T")) {
            val scheduledDt = LocalDateTime.parse(
                scheduledTime.replace("Z", "").substringBefore("+"),
                DateTimeFormatter.ISO_LOCAL_DATE_TIME
            )
            scheduledDt.hour * 60 + scheduledDt.minute
        } else {
            // HH:mm format
            val parts = scheduledTime.split(":")
            if (parts.size >= 2) {
                (parts[0].toIntOrNull() ?: 8) * 60 + (parts[1].toIntOrNull() ?: 0)
            } else {
                8 * 60 // Default 8:00 AM
            }
        }
        val checkedInMinutes = checkedInDt.hour * 60 + checkedInDt.minute
        return checkedInMinutes > scheduledMinutes + 120 // >2 hours late
    } catch (_: Exception) {
        return false
    }
}

private fun buildAccessibilityDescription(gridData: List<List<CellData?>>): String {
    val sb = StringBuilder("Check-in calendar heatmap. ")
    var onTime = 0
    var late = 0
    var missed = 0
    for (week in gridData) {
        for (cell in week) {
            when (cell?.status) {
                CellStatus.ON_TIME -> onTime++
                CellStatus.LATE -> late++
                CellStatus.MISSED -> missed++
                else -> {}
            }
        }
    }
    sb.append("$onTime on time, $late late, $missed missed.")
    return sb.toString()
}
