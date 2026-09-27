import SwiftUI

/// A GitHub-style calendar heatmap: one cell per receiver-local day.
///
/// It draws `HistoryDay`s built by `HistoryTimeline`, so every state here —
/// including "asked for help", "reached another way" and today's "due later" —
/// is the same one the log, the summary and the PDF show, and matches the
/// dashboard. Tapping a day opens what happened that day.
struct CalendarHeatmapView: View {
    let days: [HistoryDay]
    /// IANA timezone of the receiver: the days were bucketed in it, so month
    /// and weekday labels are read in it too.
    var timezone: String? = nil
    /// One-sentence summary VoiceOver reads for the whole grid.
    var accessibilitySummary: String = ""
    var onSelect: (HistoryDay) -> Void = { _ in }

    @Environment(\.colorSchemeContrast) private var contrast
    // Scale the grid with Dynamic Type instead of fixed point sizes so the
    // heatmap remains legible at larger text sizes (US-IOS105). The grid
    // scrolls horizontally (anchored to today), so large sizes no longer clip
    // the most recent weeks off the right edge.
    @ScaledMetric(relativeTo: .caption2) private var cellSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var spacing: CGFloat = 3
    @ScaledMetric(relativeTo: .caption2) private var symbolSize: CGFloat = 7
    @ScaledMetric(relativeTo: .caption2) private var dayLabelSize: CGFloat = 9
    @ScaledMetric(relativeTo: .caption2) private var monthLabelHeight: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var legendSwatch: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var legendSymbolSize: CGFloat = 6

    var body: some View {
        let calendar = Calendar.forTimezone(timezone)
        let columns = Self.columns(for: days, calendar: calendar)
        let monthLabels = Self.monthLabels(for: columns, calendar: calendar)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Check-In Calendar")
                .font(.headline)

            HStack(alignment: .top, spacing: spacing) {
                // Weekday labels (Sunday-first rows, matching the grid).
                VStack(alignment: .trailing, spacing: spacing) {
                    Color.clear.frame(height: monthLabelHeight)
                    ForEach(0..<7, id: \.self) { row in
                        Text(row % 2 == 1 ? calendar.veryShortWeekdaySymbols[row] : "")
                            .font(.system(size: dayLabelSize))
                            .foregroundStyle(.secondary)
                            .frame(height: cellSize)
                    }
                }
                .accessibilityHidden(true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(columns.indices, id: \.self) { col in
                            VStack(alignment: .leading, spacing: spacing) {
                                Text(monthLabels[col] ?? "")
                                    .font(.system(size: dayLabelSize))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                    .frame(width: cellSize, height: monthLabelHeight, alignment: .bottomLeading)
                                ForEach(0..<7, id: \.self) { row in
                                    cell(columns[col][row])
                                }
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
                .defaultScrollAnchor(.trailing)
            }
            // One stop for VoiceOver instead of ~100 undated cells; every day
            // with something in it is also in the log below, with its date.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Each day is listed in the check-in log below.")

            // Legend — wraps instead of running off the card at large sizes.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                legendItem(.onTime, label: "Checked in")
                legendItem(.late, label: "After an alert")
                legendItem(.missed, label: "Missed")
                legendItem(.stoodDown, label: "Reached another way")
                legendItem(.needsHelp, label: "Asked for help")
                legendItem(.waiting, label: "Waiting for an answer")
                legendItem(.notAsked, label: "No check-in asked")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level2)
    }

    // MARK: - Cells

    @ViewBuilder
    private func cell(_ day: HistoryDay?) -> some View {
        if let day {
            Button {
                onSelect(day)
            } label: {
                swatch(day.status, isToday: day.isToday, size: cellSize, glyphSize: symbolSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            // Padding before the first day / after today.
            Color.clear.frame(width: cellSize, height: cellSize)
        }
    }

    private func swatch(_ status: HistoryDayStatus, isToday: Bool, size: CGFloat, glyphSize: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(fill(status))
            if isToday {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.primary, lineWidth: 1.5)
            }
            Text(Self.glyph(status))
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(glyphColor(status))
        }
        .frame(width: size, height: size)
    }

    private func legendItem(_ status: HistoryDayStatus, label: String) -> some View {
        HStack(spacing: 4) {
            swatch(status, isToday: false, size: legendSwatch, glyphSize: legendSymbolSize)
            // Lead with the label text so the legend isn't color-only.
            Text(label)
        }
    }

    // MARK: - Styling

    private func fill(_ status: HistoryDayStatus) -> Color {
        switch status {
        case .onTime: return .green
        case .late: return .yellow
        case .missed, .needsHelp: return .red
        case .stoodDown: return .red.opacity(0.3)
        case .waiting: return DailyOKColor.warning
        case .notAsked: return Color(.systemGray5)
        case .dueLater: return Color(.systemGray6)
        }
    }

    /// Each state has its own glyph, so none is told apart by color alone
    /// (missed ✗ and help ‼ share red on purpose — both are urgent, as on the
    /// dashboard).
    nonisolated static func glyph(_ status: HistoryDayStatus) -> String {
        switch status {
        case .onTime: return "\u{2713}"
        case .late: return "!"
        case .missed: return "\u{2717}"
        case .needsHelp: return "\u{203C}"
        case .stoodDown: return "\u{2013}"
        case .waiting: return "\u{2026}"
        case .notAsked, .dueLater: return ""
        }
    }

    /// Dark glyphs on the light fills (yellow, amber, pale red), white on the
    /// saturated ones. Full opacity under Increase Contrast (US-IOS106).
    private func glyphColor(_ status: HistoryDayStatus) -> Color {
        let base: Color
        switch status {
        case .late, .waiting: base = Color(red: 0.35, green: 0.25, blue: 0.0)
        case .stoodDown: base = Color(red: 0.55, green: 0.0, blue: 0.0)
        default: base = .white
        }
        return contrast == .increased ? base : base.opacity(status == .onTime || status == .missed || status == .needsHelp ? 0.9 : 1.0)
    }

    // MARK: - Layout (pure)

    /// Week columns of 7 Sunday-first rows. nil = padding before the first day
    /// or after today.
    nonisolated static func columns(for days: [HistoryDay], calendar: Calendar) -> [[HistoryDay?]] {
        guard let first = days.first else { return [] }
        let lead = calendar.component(.weekday, from: first.date) - 1 // 0 = Sunday
        var cells: [HistoryDay?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    /// A month name over the column where that month starts (and over the
    /// first column, unless a month starts right after it and would collide).
    /// Derived from the real columns, so labels can't drift from their cells.
    nonisolated static func monthLabels(for columns: [[HistoryDay?]], calendar: Calendar) -> [String?] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")

        let starts: [Date?] = columns.map { column in
            column.compactMap { $0 }.first { calendar.component(.day, from: $0.date) == 1 }?.date
        }
        return columns.indices.map { index in
            if let start = starts[index] { return formatter.string(from: start) }
            if index == 0, let first = columns[0].compactMap({ $0 }).first {
                let collides = starts.prefix(3).dropFirst().contains { $0 != nil }
                return collides ? nil : formatter.string(from: first.date)
            }
            return nil
        }
    }
}
