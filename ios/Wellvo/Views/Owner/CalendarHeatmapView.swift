import SwiftUI

/// A GitHub-style calendar heatmap showing check-in status per day.
/// Green = on time, Yellow = late, Red = missed, Gray = no data.
struct CalendarHeatmapView: View {
    let checkIns: [CheckIn]
    let days: Int
    let scheduledTime: String? // HH:mm format, used to determine "late"

    private let cellSize: CGFloat = 14
    private let spacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check-In Calendar")
                .font(.headline)

            // Month labels
            HStack(spacing: 0) {
                ForEach(monthLabels(), id: \.offset) { label in
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
                let grid = buildGrid()
                ForEach(0..<grid.count, id: \.self) { weekIndex in
                    VStack(spacing: spacing) {
                        ForEach(0..<grid[weekIndex].count, id: \.self) { dayIndex in
                            let entry = grid[weekIndex][dayIndex]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForStatus(entry.status))
                                .frame(width: cellSize, height: cellSize)
                                .help(entry.tooltip)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendItem(color: .gray.opacity(0.15), label: "No data")
                legendItem(color: .green, label: "On time")
                legendItem(color: .yellow, label: "Late")
                legendItem(color: .red, label: "Missed")
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -days, to: today)!

        // Build check-in lookup by day
        var checkInByDay: [Date: CheckIn] = [:]
        for checkIn in checkIns {
            let day = calendar.startOfDay(for: checkIn.checkedInAt)
            if checkInByDay[day] == nil {
                checkInByDay[day] = checkIn
            }
        }

        // Parse scheduled time for "late" detection
        let scheduledMinutes = parseTimeToMinutes(scheduledTime ?? "08:00")
        let lateThreshold = scheduledMinutes + 120 // 2 hours after scheduled = "late"

        // Build entries
        var entries: [DayEntry] = []
        var current = startDate
        while current <= today {
            let status: DayStatus
            let tooltip: String

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
            } else {
                status = .missed
                tooltip = "\(formatDate(current)): Missed"
            }

            entries.append(DayEntry(date: current, status: status, tooltip: tooltip))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -days, to: today)!

        var labels: [(offset: Int, name: String, weeks: Int)] = []
        var current = startDate
        var currentMonth = calendar.component(.month, from: current)
        var weekCount = 0
        var offset = 0

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        while current <= today {
            let month = calendar.component(.month, from: current)
            if month != currentMonth {
                labels.append((offset: offset, name: monthFormatter.string(from: calendar.date(byAdding: .day, value: -1, to: current)!), weeks: max(1, weekCount / 7)))
                offset += weekCount / 7
                weekCount = 0
                currentMonth = month
            }
            weekCount += 1
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        labels.append((offset: offset, name: monthFormatter.string(from: today), weeks: max(1, weekCount / 7)))

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

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
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
