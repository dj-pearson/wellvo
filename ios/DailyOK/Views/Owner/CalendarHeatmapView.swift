import SwiftUI

/// A GitHub-style calendar heatmap showing check-in status per day.
/// Green = on time, Yellow = late, Red = missed, Gray = no data.
struct CalendarHeatmapView: View {
    let checkIns: [CheckIn]
    let days: Int
    let scheduledTime: String? // HH:mm format, used to determine "late"
    /// IANA timezone of the receiver. Buckets days and judges on-time/late in
    /// the receiver's zone, not the owner's device zone.
    var timezone: String? = nil
    /// Day the receiver joined. Days before this render as "no data", not "missed".
    var enrolledSince: Date? = nil
    /// Calendar weekday numbers (1=Sun…7=Sat) on which a check-in is scheduled.
    /// Days off the schedule (weekend-only/custom/paused) render as "no data".
    /// Nil means every day is scheduled (legacy behavior).
    var scheduledWeekdays: Set<Int>? = nil
    /// Full receiver settings, used to resolve the per-day scheduled time for the
    /// "late" threshold on weekday_weekend / custom schedules (US-IOS101). When
    /// nil, falls back to the single `scheduledTime` for every day.
    var settings: ReceiverSettings? = nil

    private let cellSize: CGFloat = 14
    private let spacing: CGFloat = 3

    var body: some View {
        // Compute the grid and month labels once per body evaluation instead of
        // rebuilding them inline (buildGrid is O(days)).
        let grid = buildGrid()
        let labels = monthLabels()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Check-In Calendar")
                .font(.headline)

            // Month labels
            HStack(spacing: 0) {
                ForEach(labels, id: \.offset) { label in
                    Text(label.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: CGFloat(label.weeks) * (cellSize + spacing), alignment: .leading)
                }
            }

            // Day-of-week labels + grid
            HStack(alignment: .top, spacing: spacing) {
                // Day labels
                VStack(spacing: spacing) {
                    ForEach(["", "M", "", "W", "", "F", ""], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: cellSize)
                    }
                }

                // Heatmap grid
                ForEach(0..<grid.count, id: \.self) { weekIndex in
                    VStack(spacing: spacing) {
                        ForEach(0..<grid[weekIndex].count, id: \.self) { dayIndex in
                            let entry = grid[weekIndex][dayIndex]
                            ZStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorForStatus(entry.status))
                                    .frame(width: cellSize, height: cellSize)

                                Text(symbolForStatus(entry.status))
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .help(entry.tooltip)
                            .accessibilityLabel(entry.tooltip.isEmpty ? "No data" : entry.tooltip)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendItem(color: .gray.opacity(0.15), label: "No data", symbol: "")
                legendItem(color: .green, label: "On time", symbol: "\u{2713}")
                legendItem(color: .yellow, label: "Late", symbol: "!")
                legendItem(color: .red, label: "Missed", symbol: "\u{2717}")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Grid Building

    private struct DayEntry {
        let date: Date
        let status: DayStatus
        let tooltip: String
    }

    private enum DayStatus {
        case noData
        case onTime
        case late
        case missed
        case future
    }

    private func buildGrid() -> [[DayEntry]] {
        let calendar = Calendar.forTimezone(timezone)
        let today = calendar.startOfDay(for: Date())
        // Render exactly `days` cells ending today (start..today inclusive == days),
        // not days+1 — otherwise the oldest column is mis-rendered (US-IOS101).
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let enrollDay = enrolledSince.map { calendar.startOfDay(for: $0) }

        // Build check-in lookup by day
        var checkInByDay: [Date: CheckIn] = [:]
        for checkIn in checkIns {
            let day = calendar.startOfDay(for: checkIn.checkedInAt)
            if checkInByDay[day] == nil {
                checkInByDay[day] = checkIn
            }
        }

        // Build entries
        var entries: [DayEntry] = []
        var current = startDate
        while current <= today {
            let status: DayStatus
            let tooltip: String

            // Resolve the "late" threshold per day from the schedule (weekday vs
            // weekend vs custom), not a single weekday time for every day.
            let lateThreshold = scheduledMinutes(for: current, calendar: calendar) + 120

            if current > today {
                status = .future
                tooltip = ""
            } else if let checkIn = checkInByDay[current] {
                let checkInMinutes = calendar.component(.hour, from: checkIn.checkedInAt) * 60
                    + calendar.component(.minute, from: checkIn.checkedInAt)

                if checkInMinutes <= lateThreshold {
                    status = .onTime
                    tooltip = "\(formatDate(current)): Checked in at \(formatTime(checkIn.checkedInAt))"
                } else {
                    status = .late
                    tooltip = "\(formatDate(current)): Late check-in at \(formatTime(checkIn.checkedInAt))"
                }
            } else if let enrollDay, current < enrollDay {
                // Before the receiver joined — there was nothing to miss.
                status = .noData
                tooltip = ""
            } else if let scheduledWeekdays,
                      !scheduledWeekdays.contains(calendar.component(.weekday, from: current)) {
                // No check-in was scheduled this day (weekend-only/custom/paused).
                status = .noData
                tooltip = ""
            } else {
                status = .missed
                tooltip = "\(formatDate(current)): Missed"
            }

            entries.append(DayEntry(date: current, status: status, tooltip: tooltip))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        // Pad the beginning to align with the correct day of the week
        let firstDayWeekday = calendar.component(.weekday, from: startDate) - 1 // 0 = Sunday
        let paddedEntries = Array(repeating: DayEntry(date: startDate, status: .noData, tooltip: ""), count: firstDayWeekday) + entries

        // Split into weeks (columns of 7)
        var weeks: [[DayEntry]] = []
        var week: [DayEntry] = []
        for (index, entry) in paddedEntries.enumerated() {
            week.append(entry)
            if (index + 1) % 7 == 0 {
                weeks.append(week)
                week = []
            }
        }
        if !week.isEmpty {
            // Pad last week
            while week.count < 7 {
                week.append(DayEntry(date: Date(), status: .future, tooltip: ""))
            }
            weeks.append(week)
        }

        return weeks
    }

    private func monthLabels() -> [(offset: Int, name: String, weeks: Int)] {
        let calendar = Calendar.forTimezone(timezone)
        let today = calendar.startOfDay(for: Date())
        // Match buildGrid's exact `days`-cell window (US-IOS101).
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today

        var labels: [(offset: Int, name: String, weeks: Int)] = []
        var current = startDate
        var currentMonth = calendar.component(.month, from: current)
        var weekCount = 0
        var offset = 0

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        // Number of week-columns a run of `dayCount` days occupies — round UP so a
        // partial trailing week still gets a column, otherwise month labels are
        // undersized and drift left of their cells (US-IOS101).
        func weekColumns(_ dayCount: Int) -> Int {
            max(1, Int((Double(dayCount) / 7.0).rounded(.up)))
        }

        while current <= today {
            let month = calendar.component(.month, from: current)
            if month != currentMonth {
                let prevDay = calendar.date(byAdding: .day, value: -1, to: current) ?? current
                let w = weekColumns(weekCount)
                labels.append((offset: offset, name: monthFormatter.string(from: prevDay), weeks: w))
                offset += w
                weekCount = 0
                currentMonth = month
            }
            weekCount += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        labels.append((offset: offset, name: monthFormatter.string(from: today), weeks: weekColumns(weekCount)))

        return labels
    }

    // MARK: - Helpers

    private func colorForStatus(_ status: DayStatus) -> Color {
        switch status {
        case .onTime: return .green
        case .late: return .yellow
        case .missed: return .red
        case .noData: return Color(.systemGray5)
        case .future: return Color(.systemGray6)
        }
    }

    private func symbolForStatus(_ status: DayStatus) -> String {
        switch status {
        case .onTime: return "\u{2713}"
        case .late: return "!"
        case .missed: return "\u{2717}"
        case .noData, .future: return ""
        }
    }

    private func legendItem(color: Color, label: String, symbol: String = "") -> some View {
        HStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 10, height: 10)
                if !symbol.isEmpty {
                    Text(symbol)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            Text(label)
        }
    }

    /// Scheduled minutes-of-day for a given date, resolved against the receiver's
    /// schedule type (US-IOS101). Falls back to the single `scheduledTime`.
    private func scheduledMinutes(for date: Date, calendar: Calendar) -> Int {
        let fallback = parseTimeToMinutes(scheduledTime ?? "08:00")
        guard let settings else { return fallback }
        let weekday = calendar.component(.weekday, from: date) // 1=Sun…7=Sat
        switch settings.scheduleType {
        case .daily:
            return parseTimeToMinutes(settings.checkinTime)
        case .weekdayWeekend:
            let isWeekend = (weekday == 1 || weekday == 7)
            let time = isWeekend ? (settings.weekendCheckinTime ?? settings.checkinTime) : settings.checkinTime
            return parseTimeToMinutes(time)
        case .custom:
            let key = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][weekday - 1]
            if let earliest = settings.customSchedule?.times(forDayKey: key).first {
                return parseTimeToMinutes(earliest)
            }
            return fallback
        }
    }

    private func parseTimeToMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return 480 } // default 8:00
        return h * 60 + m
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
