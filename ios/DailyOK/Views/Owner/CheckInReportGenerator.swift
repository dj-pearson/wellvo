import SwiftUI
import PDFKit

/// Generates a PDF report of check-in history for sharing with
/// healthcare providers or family meetings.
///
/// Intentionally NOT `@MainActor`: generation is pure CPU work (UIKit/Core Text
/// drawing into a self-contained `UIGraphicsPDFRenderer` context) and is run off
/// the main actor so a large report can't freeze the UI. It uses explicit print
/// colors rather than dynamic system colors so the output is deterministic and
/// appearance-independent (a dynamic `.label` would resolve to white in dark mode
/// and render invisible on the white PDF page).
struct CheckInReportGenerator {

    // Fixed "ink" colors for a printable page — independent of app appearance
    // and safe to use off the main actor (no trait-collection resolution).
    private static let inkPrimary = UIColor(white: 0.10, alpha: 1)
    private static let inkSecondary = UIColor(white: 0.40, alpha: 1)
    private static let inkTertiary = UIColor(white: 0.58, alpha: 1)
    private static let rule = UIColor(white: 0.80, alpha: 1)

    struct ReportData: Sendable {
        let receiverName: String
        let familyName: String
        let checkIns: [CheckIn]
        let periodDays: Int
        let generatedAt: Date
        /// The receiver's IANA timezone. Days, streak, and average time must be
        /// bucketed in the receiver's zone so the report matches the dashboard
        /// for an owner in a different region (US-IOS100). nil = device zone.
        let timezone: String?
        /// The window's days from `HistoryTimeline` (oldest first) — the same
        /// model the History screen draws, so the report's missed days, help
        /// requests and counts match it. Empty = legacy caller: the log lists
        /// check-ins only and the summary counts calendar days.
        var days: [HistoryDay] = []
        /// Current streak by the dashboard's rule, computed by the caller from
        /// all the history it holds. nil = computed here from `checkIns`.
        var streak: Int? = nil
    }

    /// One row of the report's daily log.
    struct ReportRow: Equatable, Sendable {
        let date: String
        let time: String
        let event: String
        let mood: String
    }

    /// A calendar fixed to the receiver's timezone (falls back to the device's).
    private static func calendar(for timezone: String?) -> Calendar {
        var calendar = Calendar.current
        if let id = timezone, let tz = TimeZone(identifier: id) {
            calendar.timeZone = tz
        }
        return calendar
    }

    static func generatePDF(from data: ReportData) -> Data {
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let pdfRenderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        let pdfData = pdfRenderer.pdfData { context in
            context.beginPage()
            var yPosition: CGFloat = margin

            // Title
            let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: inkPrimary,
            ]
            let title = "Daily OK Check-In Report"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttrs)
            yPosition += 36

            // Subtitle
            let subtitleFont = UIFont.systemFont(ofSize: 14)
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: inkSecondary,
            ]
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long

            let subtitle = "\(data.receiverName) — \(data.familyName)"
            subtitle.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttrs)
            yPosition += 22

            let reportCalendar = Self.calendar(for: data.timezone)
            dateFormatter.timeZone = reportCalendar.timeZone
            // The same `periodDays`-day window the History screen draws
            // (today and the days before it), not `generatedAt - periodDays`,
            // which printed a period one day longer than the data.
            let window = HistoryTimeline.window(days: data.periodDays, now: data.generatedAt, calendar: reportCalendar)
            let periodEnd = dateFormatter.string(from: data.generatedAt)
            let periodStart = dateFormatter.string(from: window.start)
            let period = "Period: \(periodStart) — \(periodEnd)"
            period.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttrs)
            yPosition += 30

            // Divider
            drawLine(in: context.cgContext, from: CGPoint(x: margin, y: yPosition), to: CGPoint(x: pageWidth - margin, y: yPosition))
            yPosition += 16

            // Summary stats (bucketed in the receiver's timezone).
            let sectionFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
            let sectionAttrs: [NSAttributedString.Key: Any] = [.font: sectionFont, .foregroundColor: inkPrimary]
            let bodyFont = UIFont.systemFont(ofSize: 12)
            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: inkPrimary]

            "Summary".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionAttrs)
            yPosition += 24

            for line in summaryLines(for: data, calendar: reportCalendar) {
                line.draw(at: CGPoint(x: margin + 16, y: yPosition), withAttributes: bodyAttrs)
                yPosition += 18
            }
            yPosition += 12

            drawLine(in: context.cgContext, from: CGPoint(x: margin, y: yPosition), to: CGPoint(x: pageWidth - margin, y: yPosition))
            yPosition += 16

            // Daily log table header
            "Daily Log".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionAttrs)
            yPosition += 24

            // Table header
            let headerFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: inkSecondary,
            ]

            let columns: [(String, CGFloat)] = [
                ("Date", margin),
                ("Time", margin + contentWidth * 0.22),
                ("What happened", margin + contentWidth * 0.37),
                ("Mood", margin + contentWidth * 0.84),
            ]
            let eventWidth = contentWidth * (0.84 - 0.37) - 8

            // Draw the column header + rule at the current yPosition. Called on
            // the first page AND after every page break so pages 2+ aren't
            // unlabeled columns.
            func drawTableHeader() {
                for (label, x) in columns {
                    label.draw(at: CGPoint(x: x, y: yPosition), withAttributes: headerAttrs)
                }
                yPosition += 16
                drawLine(in: context.cgContext, from: CGPoint(x: margin, y: yPosition), to: CGPoint(x: pageWidth - margin, y: yPosition), color: rule)
                yPosition += 6
            }

            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: inkTertiary,
            ]
            // Name the zone the times are in. A clinician reading "8:15 AM"
            // has no way to know whose clock it is, and the answer is not the
            // reader's — it is the receiver's.
            let zoneNote = reportCalendar.timeZone.localizedName(for: .shortStandard, locale: .current)
                ?? reportCalendar.timeZone.identifier
            let footerText = "Generated by Daily OK on \(dateFormatter.string(from: data.generatedAt)) — times shown in \(zoneNote) — dailyok.net"
            // Footer pinned to the page bottom; drawn on every page, not just the last.
            func drawFooter() {
                footerText.draw(at: CGPoint(x: margin, y: pageHeight - margin), withAttributes: footerAttrs)
            }

            drawTableHeader()

            // Table rows
            let rowFont = UIFont.systemFont(ofSize: 10)
            let rowAttrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: inkPrimary]

            // Locale-aware date/time in the exported report (US-IOS044), in the
            // RECEIVER's timezone (US-IOS100) — the footer names the zone.
            // The log includes missed and stood-down requests and help
            // requests, not only successful check-ins: a report that lists
            // "I need help" as an ordinary check-in, and leaves missed days out
            // entirely, is the opposite of what a clinician needs.
            let rows = data.days.isEmpty
                ? legacyRows(checkIns: data.checkIns, periodDays: data.periodDays, now: data.generatedAt, calendar: reportCalendar)
                : reportRows(days: data.days, calendar: reportCalendar)

            for row in rows {
                if yPosition > pageHeight - margin - 30 {
                    // Footer on the page we're leaving, then a fresh page with the
                    // column header repeated.
                    drawFooter()
                    context.beginPage()
                    yPosition = margin
                    drawTableHeader()
                }

                row.date.draw(at: CGPoint(x: columns[0].1, y: yPosition), withAttributes: rowAttrs)
                row.time.draw(at: CGPoint(x: columns[1].1, y: yPosition), withAttributes: rowAttrs)
                (row.event as NSString).draw(
                    with: CGRect(x: columns[2].1, y: yPosition, width: eventWidth, height: 14),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: rowAttrs,
                    context: nil
                )
                row.mood.draw(at: CGPoint(x: columns[3].1, y: yPosition), withAttributes: rowAttrs)
                yPosition += 16
            }

            // Footer on the final page.
            drawFooter()
        }

        return pdfData
    }

    // MARK: - Helpers

    private static func drawLine(in context: CGContext, from: CGPoint, to: CGPoint, color: UIColor = rule) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.5)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
    }

    /// The average clock time of a set of check-ins, in the receiver's zone and
    /// the reader's locale.
    ///
    /// It used to build the string by hand — `"\(h):\(m) \(h >= 12 ? "PM" : "AM")"`
    /// — directly beneath a comment noting that the report's dates are
    /// locale-aware. So a reader on a 24-hour clock got a report whose table
    /// read "21:14" and whose summary line, three inches above, read "9:14 PM".
    ///
    /// Internal rather than private so it can be tested without rendering a PDF.
    static func averageCheckInTime(
        _ checkIns: [CheckIn],
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        guard !checkIns.isEmpty else { return "—" }
        let totalMinutes = checkIns.reduce(0) { sum, ci in
            let c = calendar.dateComponents([.hour, .minute], from: ci.checkedInAt)
            return sum + (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let avg = totalMinutes / checkIns.count

        // Round-trip the average through a real date so DateFormatter can render
        // it: components are built and read back in the same calendar, so the
        // wall-clock value survives regardless of zone.
        var components = DateComponents()
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = avg / 60
        components.minute = avg % 60
        guard let date = calendar.date(from: components) else { return "—" }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func moodBreakdownString(_ checkIns: [CheckIn]) -> String {
        var counts: [String: Int] = [:]
        for ci in checkIns {
            if let mood = ci.mood, mood != .unknown {
                counts[mood.label, default: 0] += 1
            }
        }
        if counts.isEmpty { return "No mood data" }
        // Stable order (most frequent first, then by name): a dictionary's
        // order changed between two exports of the same data.
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }

    /// Check-ins inside the report's window only. The fetch can reach into the
    /// day before the window, which printed "Days Checked In: 31 / 30".
    static func checkInsInWindow(_ checkIns: [CheckIn], periodDays: Int, now: Date, calendar: Calendar) -> [CheckIn] {
        let window = HistoryTimeline.window(days: periodDays, now: now, calendar: calendar)
        let latest = now.addingTimeInterval(HistoryTimeline.futureTolerance)
        return checkIns.filter { $0.checkedInAt >= window.start && $0.checkedInAt < window.end && $0.checkedInAt <= latest }
    }

    /// The summary block. Internal so it can be tested without rendering.
    static func summaryLines(for data: ReportData, calendar: Calendar) -> [String] {
        let inWindow = checkInsInWindow(data.checkIns, periodDays: data.periodDays, now: data.generatedAt, calendar: calendar)
        // First check-in of each day, so a second window or an on-demand
        // answer doesn't drag the "usual" time toward the afternoon.
        var firstByDay: [Date: CheckIn] = [:]
        for ci in inWindow {
            let day = calendar.startOfDay(for: ci.checkedInAt)
            if let existing = firstByDay[day], existing.checkedInAt <= ci.checkedInAt { continue }
            firstByDay[day] = ci
        }
        let streak = data.streak ?? HistoryTimeline.currentStreak(checkIns: data.checkIns, now: data.generatedAt, calendar: calendar)

        var lines: [String] = []
        if data.days.isEmpty {
            let daysWithCheckIn = firstByDay.count
            let consistency = data.periodDays > 0 ? min(100.0, Double(daysWithCheckIn) / Double(data.periodDays) * 100) : 0
            lines.append("Days Checked In: \(daysWithCheckIn) / \(data.periodDays)")
            lines.append("Consistency: \(String(format: "%.0f", consistency))%")
        } else {
            let stats = HistoryTimeline.stats(for: data.days)
            if let percent = stats.percent {
                lines.append("Checked in on \(stats.answeredDays) of \(stats.expectedDays) days a check-in was due (\(percent)%)")
            } else {
                lines.append("No check-ins were due in this period")
            }
            var missed = "Missed days: \(stats.missedDays + stats.stoodDownDays)"
            if stats.stoodDownDays > 0 {
                missed += " (\(stats.stoodDownDays) reached another way by family)"
            }
            lines.append(missed)
            lines.append("Answered only after the family was alerted: \(stats.lateDays)")
            lines.append("Help requests (need help / call me / SOS): \(stats.helpRequests)")
        }
        lines.append("Total Check-Ins: \(inWindow.count)")
        lines.append("Usual First Check-In Time: \(averageCheckInTime(Array(firstByDay.values), calendar: calendar))")
        lines.append("Mood Breakdown: \(moodBreakdownString(inWindow))")
        lines.append("Current Streak: \(streak) day(s)")
        return lines
    }

    /// Daily log rows from the History model, newest first.
    static func reportRows(days: [HistoryDay], calendar: Calendar, locale: Locale = .current) -> [ReportRow] {
        let (dateFmt, timeFmt) = rowFormatters(calendar: calendar, locale: locale)
        return days.reversed().flatMap { day in
            day.events.reversed().map { event -> ReportRow in
                var mood = "—"
                if case .checkIn(let checkIn, _, _) = event.kind, let m = checkIn.mood, m != .unknown {
                    mood = m.label
                }
                return ReportRow(
                    date: dateFmt.string(from: event.at),
                    time: timeFmt.string(from: event.at),
                    event: HistoryTimeline.title(for: event),
                    mood: mood
                )
            }
        }
    }

    /// Check-in-only rows, for a caller that doesn't pass `days`.
    static func legacyRows(checkIns: [CheckIn], periodDays: Int, now: Date, calendar: Calendar, locale: Locale = .current) -> [ReportRow] {
        let (dateFmt, timeFmt) = rowFormatters(calendar: calendar, locale: locale)
        return checkInsInWindow(checkIns, periodDays: periodDays, now: now, calendar: calendar)
            .sorted { $0.checkedInAt > $1.checkedInAt }
            .map { checkIn in
                let event = HistoryEvent(
                    id: "ci-\(checkIn.id)", at: checkIn.checkedInAt,
                    kind: .checkIn(checkIn, help: DashboardViewModel.helpKind(for: checkIn), afterAlert: false)
                )
                return ReportRow(
                    date: dateFmt.string(from: checkIn.checkedInAt),
                    time: timeFmt.string(from: checkIn.checkedInAt),
                    event: HistoryTimeline.title(for: event),
                    mood: checkIn.mood.flatMap { $0 == .unknown ? nil : $0.label } ?? "—"
                )
            }
    }

    private static func rowFormatters(calendar: Calendar, locale: Locale) -> (DateFormatter, DateFormatter) {
        let dateFmt = DateFormatter()
        dateFmt.calendar = calendar
        dateFmt.timeZone = calendar.timeZone
        dateFmt.locale = locale
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .none
        let timeFmt = DateFormatter()
        timeFmt.calendar = calendar
        timeFmt.timeZone = calendar.timeZone
        timeFmt.locale = locale
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short
        return (dateFmt, timeFmt)
    }

    /// A file name the share sheet, Mail and Files can show:
    /// "Daily OK – Mom – Aug 29–Sep 27.pdf".
    static func fileName(receiverName: String, start: Date, end: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        let safeName = receiverName
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let name = safeName.isEmpty ? "Report" : safeName
        return "Daily OK – \(name) – \(formatter.string(from: start))–\(formatter.string(from: end)).pdf"
    }
}
