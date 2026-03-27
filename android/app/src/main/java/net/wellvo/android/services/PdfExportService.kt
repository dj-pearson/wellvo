package net.wellvo.android.services

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import net.wellvo.android.data.models.CheckIn
import net.wellvo.android.data.models.CheckInSource
import net.wellvo.android.data.models.emoji
import java.io.File
import java.io.FileOutputStream
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

class PdfExportService {

    companion object {
        private const val PAGE_WIDTH = 595  // A4 portrait in points
        private const val PAGE_HEIGHT = 842
        private const val MARGIN = 40f
        private const val CONTENT_WIDTH = PAGE_WIDTH - 2 * MARGIN

        private val WELLVO_GREEN = Color.rgb(34, 197, 94)
        private val HEADER_COLOR = Color.rgb(34, 197, 94)
        private val TEXT_COLOR = Color.rgb(31, 41, 55)
        private val SUBTEXT_COLOR = Color.rgb(107, 114, 128)
        private val BORDER_COLOR = Color.rgb(229, 231, 235)
        private val ROW_ALT_COLOR = Color.rgb(249, 250, 251)

        private val HEATMAP_ON_TIME = Color.rgb(34, 197, 94)
        private val HEATMAP_LATE = Color.rgb(245, 158, 11)
        private val HEATMAP_MISSED = Color.rgb(239, 68, 68)
        private val HEATMAP_NO_DATA = Color.rgb(229, 231, 235)

        fun export(
            context: Context,
            familyName: String,
            receiverName: String,
            days: Int,
            checkIns: List<CheckIn>
        ): File {
            val doc = PdfDocument()
            val pages = mutableListOf<PdfDocument.Page>()

            var pageNum = 1
            var page = doc.startPage(
                PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNum).create()
            )
            var canvas = page.canvas
            var y = MARGIN

            // Header
            y = drawHeader(canvas, y, familyName, receiverName, days)
            y += 16f

            // Summary stats
            y = drawSummaryStats(canvas, y, checkIns)
            y += 16f

            // Heatmap grid
            y = drawHeatmapGrid(canvas, y, checkIns, days)
            y += 20f

            // Check-in log table header
            y = drawTableHeader(canvas, y)

            // Check-in log rows
            val sortedCheckIns = checkIns.sortedByDescending { it.checkedInAt }
            for ((index, checkIn) in sortedCheckIns.withIndex()) {
                val rowHeight = 28f
                if (y + rowHeight > PAGE_HEIGHT - MARGIN - 30f) {
                    // Finish current page, start new one
                    drawFooter(canvas, pageNum)
                    doc.finishPage(page)
                    pages.add(page)
                    pageNum++
                    page = doc.startPage(
                        PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNum).create()
                    )
                    canvas = page.canvas
                    y = MARGIN
                    y = drawTableHeader(canvas, y)
                }
                y = drawCheckInRow(canvas, y, checkIn, index % 2 == 1)
            }

            // Footer on last page
            drawFooter(canvas, pageNum)
            doc.finishPage(page)

            // Save to cache
            val exportDir = File(context.cacheDir, "pdf_exports")
            exportDir.mkdirs()
            val dateStr = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
            val fileName = "Wellvo_${receiverName.replace(" ", "_")}_${dateStr}.pdf"
            val file = File(exportDir, fileName)
            FileOutputStream(file).use { doc.writeTo(it) }
            doc.close()

            return file
        }

        private fun drawHeader(canvas: Canvas, startY: Float, familyName: String, receiverName: String, days: Int): Float {
            var y = startY

            // Wellvo title
            val titlePaint = Paint().apply {
                color = HEADER_COLOR
                textSize = 24f
                isFakeBoldText = true
                isAntiAlias = true
            }
            canvas.drawText("Wellvo", MARGIN, y + 24f, titlePaint)

            // Subtitle
            val subtitlePaint = Paint().apply {
                color = SUBTEXT_COLOR
                textSize = 10f
                isAntiAlias = true
            }
            canvas.drawText("Check-in History Report", MARGIN, y + 40f, subtitlePaint)
            y += 52f

            // Divider line
            val linePaint = Paint().apply {
                color = WELLVO_GREEN
                strokeWidth = 2f
            }
            canvas.drawLine(MARGIN, y, PAGE_WIDTH - MARGIN, y, linePaint)
            y += 16f

            // Info section
            val infoPaint = Paint().apply {
                color = TEXT_COLOR
                textSize = 11f
                isAntiAlias = true
            }
            val labelPaint = Paint().apply {
                color = SUBTEXT_COLOR
                textSize = 10f
                isAntiAlias = true
            }

            canvas.drawText("Family:", MARGIN, y, labelPaint)
            canvas.drawText(familyName, MARGIN + 60f, y, infoPaint)
            y += 16f

            canvas.drawText("Receiver:", MARGIN, y, labelPaint)
            canvas.drawText(receiverName, MARGIN + 60f, y, infoPaint)
            y += 16f

            val today = LocalDate.now()
            val startDate = today.minusDays(days.toLong() - 1)
            val dateFormat = DateTimeFormatter.ofPattern("MMM d, yyyy")
            canvas.drawText("Period:", MARGIN, y, labelPaint)
            canvas.drawText("${startDate.format(dateFormat)} - ${today.format(dateFormat)} ($days days)", MARGIN + 60f, y, infoPaint)
            y += 16f

            val generatedPaint = Paint().apply {
                color = SUBTEXT_COLOR
                textSize = 9f
                isAntiAlias = true
            }
            canvas.drawText("Generated: ${today.format(dateFormat)}", MARGIN, y, generatedPaint)
            y += 8f

            return y
        }

        private fun drawSummaryStats(canvas: Canvas, startY: Float, checkIns: List<CheckIn>): Float {
            var y = startY
            val sectionPaint = Paint().apply {
                color = TEXT_COLOR
                textSize = 13f
                isFakeBoldText = true
                isAntiAlias = true
            }
            canvas.drawText("Summary", MARGIN, y + 13f, sectionPaint)
            y += 24f

            val minutes = checkIns.mapNotNull { ci ->
                try {
                    val dt = LocalDateTime.parse(
                        ci.checkedInAt.replace("Z", "").substringBefore("+"),
                        DateTimeFormatter.ISO_LOCAL_DATE_TIME
                    )
                    dt.hour * 60 + dt.minute
                } catch (_: DateTimeParseException) { null }
            }

            val statPaint = Paint().apply {
                color = TEXT_COLOR
                textSize = 11f
                isAntiAlias = true
            }
            val valuePaint = Paint().apply {
                color = WELLVO_GREEN
                textSize = 11f
                isFakeBoldText = true
                isAntiAlias = true
            }

            val totalCheckIns = checkIns.size
            canvas.drawText("Total check-ins:", MARGIN, y, statPaint)
            canvas.drawText("$totalCheckIns", MARGIN + 120f, y, valuePaint)
            y += 16f

            if (minutes.isNotEmpty()) {
                val avg = minutes.average().toInt()
                canvas.drawText("Average time:", MARGIN, y, statPaint)
                canvas.drawText(formatMinutes(avg), MARGIN + 120f, y, valuePaint)
                y += 16f

                canvas.drawText("Earliest:", MARGIN, y, statPaint)
                canvas.drawText(formatMinutes(minutes.min()), MARGIN + 120f, y, valuePaint)

                canvas.drawText("Latest:", MARGIN + 250f, y, statPaint)
                canvas.drawText(formatMinutes(minutes.max()), MARGIN + 330f, y, valuePaint)
                y += 16f
            }

            // Mood breakdown
            val moods = checkIns.mapNotNull { it.mood }
            if (moods.isNotEmpty()) {
                canvas.drawText("Moods:", MARGIN, y, statPaint)
                val moodStr = moods.groupBy { it }
                    .map { (mood, list) -> "${mood.emoji()} ${list.size}" }
                    .joinToString("  ")
                canvas.drawText(moodStr, MARGIN + 120f, y, statPaint)
                y += 16f
            }

            return y
        }

        private fun drawHeatmapGrid(canvas: Canvas, startY: Float, checkIns: List<CheckIn>, days: Int): Float {
            var y = startY
            val sectionPaint = Paint().apply {
                color = TEXT_COLOR
                textSize = 13f
                isFakeBoldText = true
                isAntiAlias = true
            }
            canvas.drawText("Consistency Calendar", MARGIN, y + 13f, sectionPaint)
            y += 24f

            val today = LocalDate.now()
            val startDate = today.minusDays(days.toLong() - 1)

            val checkInDates = mutableSetOf<LocalDate>()
            for (ci in checkIns) {
                try {
                    val dt = LocalDateTime.parse(
                        ci.checkedInAt.replace("Z", "").substringBefore("+"),
                        DateTimeFormatter.ISO_LOCAL_DATE_TIME
                    )
                    checkInDates.add(dt.toLocalDate())
                } catch (_: DateTimeParseException) { /* skip */ }
            }

            val cellSize = 8f
            val cellSpacing = 2f
            val step = cellSize + cellSpacing

            // Align to Monday
            val dayOfWeek = startDate.dayOfWeek.value - 1
            val alignedStart = startDate.minusDays(dayOfWeek.toLong())

            // Day labels
            val dayLabelPaint = Paint().apply {
                color = SUBTEXT_COLOR
                textSize = 7f
                isAntiAlias = true
            }
            val dayLabels = listOf("M", "T", "W", "T", "F", "S", "S")
            for (i in dayLabels.indices) {
                canvas.drawText(dayLabels[i], MARGIN, y + i * step + cellSize, dayLabelPaint)
            }

            val gridStartX = MARGIN + 14f
            var current = alignedStart
            var week = 0
            while (!current.isAfter(today) || current.dayOfWeek.value != 1) {
                val dayIdx = current.dayOfWeek.value - 1
                val x = gridStartX + week * step
                val cellY = y + dayIdx * step

                val color = when {
                    current.isBefore(startDate) -> HEATMAP_NO_DATA
                    current.isAfter(today) -> HEATMAP_NO_DATA
                    checkInDates.contains(current) -> HEATMAP_ON_TIME
                    current.isBefore(today) -> HEATMAP_MISSED
                    else -> HEATMAP_NO_DATA
                }

                val cellPaint = Paint().apply {
                    this.color = color
                    isAntiAlias = true
                }
                canvas.drawRoundRect(
                    RectF(x, cellY, x + cellSize, cellY + cellSize),
                    2f, 2f, cellPaint
                )

                current = current.plusDays(1)
                if (current.dayOfWeek.value == 1) week++
                if (week > 14 && days <= 30) break
                if (week > 52) break
            }

            y += 7 * step + 8f

            // Legend
            val legendPaint = Paint().apply {
                color = SUBTEXT_COLOR
                textSize = 8f
                isAntiAlias = true
            }
            var lx = MARGIN
            for ((lColor, lLabel) in listOf(
                HEATMAP_ON_TIME to "On time",
                HEATMAP_LATE to "Late",
                HEATMAP_MISSED to "Missed",
                HEATMAP_NO_DATA to "No data"
            )) {
                val cellPaint = Paint().apply { this.color = lColor; isAntiAlias = true }
                canvas.drawRoundRect(RectF(lx, y, lx + 8f, y + 8f), 2f, 2f, cellPaint)
                canvas.drawText(lLabel, lx + 11f, y + 8f, legendPaint)
                lx += legendPaint.measureText(lLabel) + 24f
            }
            y += 16f

            return y
        }

        private fun drawTableHeader(canvas: Canvas, startY: Float): Float {
            var y = startY
            val headerPaint = Paint().apply {
                color = TEXT_COLOR
                textSize = 10f
                isFakeBoldText = true
                isAntiAlias = true
            }

            // Header background
            val bgPaint = Paint().apply {
                color = Color.rgb(243, 244, 246)
            }
            canvas.drawRect(MARGIN, y, PAGE_WIDTH - MARGIN, y + 20f, bgPaint)

            y += 14f
            canvas.drawText("Date", MARGIN + 4f, y, headerPaint)
            canvas.drawText("Time", MARGIN + 100f, y, headerPaint)
            canvas.drawText("Mood", MARGIN + 170f, y, headerPaint)
            canvas.drawText("Source", MARGIN + 240f, y, headerPaint)
            canvas.drawText("Response", MARGIN + 340f, y, headerPaint)
            y += 10f

            // Header underline
            val linePaint = Paint().apply {
                color = BORDER_COLOR
                strokeWidth = 1f
            }
            canvas.drawLine(MARGIN, y, PAGE_WIDTH - MARGIN, y, linePaint)

            return y
        }

        private fun drawCheckInRow(canvas: Canvas, startY: Float, checkIn: CheckIn, isAlt: Boolean): Float {
            var y = startY
            val rowHeight = 24f

            if (isAlt) {
                val bgPaint = Paint().apply { color = ROW_ALT_COLOR }
                canvas.drawRect(MARGIN, y, PAGE_WIDTH - MARGIN, y + rowHeight, bgPaint)
            }

            val textPaint = Paint().apply {
                color = TEXT_COLOR
                textSize = 10f
                isAntiAlias = true
            }

            val (dateStr, timeStr) = formatCheckInDateTime(checkIn.checkedInAt)
            val textY = y + 16f

            canvas.drawText(dateStr, MARGIN + 4f, textY, textPaint)
            canvas.drawText(timeStr, MARGIN + 100f, textY, textPaint)

            checkIn.mood?.let { mood ->
                canvas.drawText(mood.emoji(), MARGIN + 170f, textY, textPaint)
            }

            val sourceStr = when (checkIn.source) {
                CheckInSource.App -> "App"
                CheckInSource.Notification -> "Notification"
                CheckInSource.OnDemand -> "On Demand"
                CheckInSource.NeedHelp -> "Need Help"
                CheckInSource.CallMe -> "Call Me"
            }
            canvas.drawText(sourceStr, MARGIN + 240f, textY, textPaint)

            checkIn.responseType?.let { rt ->
                val rtStr = when (rt) {
                    net.wellvo.android.data.models.CheckInResponseType.Ok -> "OK"
                    net.wellvo.android.data.models.CheckInResponseType.NeedHelp -> "Need Help"
                    net.wellvo.android.data.models.CheckInResponseType.CallMe -> "Call Me"
                }
                canvas.drawText(rtStr, MARGIN + 340f, textY, textPaint)
            }

            y += rowHeight

            // Row separator
            val linePaint = Paint().apply {
                color = BORDER_COLOR
                strokeWidth = 0.5f
            }
            canvas.drawLine(MARGIN, y, PAGE_WIDTH - MARGIN, y, linePaint)

            return y
        }

        private fun drawFooter(canvas: Canvas, pageNum: Int) {
            val footerPaint = Paint().apply {
                color = SUBTEXT_COLOR
                textSize = 8f
                isAntiAlias = true
            }
            val footerY = PAGE_HEIGHT - 20f
            canvas.drawText("Generated by Wellvo", MARGIN, footerY, footerPaint)

            val pageText = "Page $pageNum"
            val pageWidth = footerPaint.measureText(pageText)
            canvas.drawText(pageText, PAGE_WIDTH - MARGIN - pageWidth, footerY, footerPaint)
        }

        private fun formatMinutes(minutes: Int): String {
            val h = minutes / 60
            val m = minutes % 60
            val amPm = if (h < 12) "AM" else "PM"
            val h12 = if (h % 12 == 0) 12 else h % 12
            return "%d:%02d %s".format(h12, m, amPm)
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
    }
}
