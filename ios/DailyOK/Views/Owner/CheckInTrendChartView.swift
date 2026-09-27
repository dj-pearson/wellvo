import SwiftUI

/// A trend line of the receiver's FIRST check-in time each day, over the
/// selected period. Uses native SwiftUI drawing — no external chart library.
///
/// Only the first check-in of each receiver-local day is used: averaging
/// every check-in put a morning-and-evening receiver's "trend" at about 2 PM,
/// a time they never check in, and let on-demand answers drag it around.
struct CheckInTrendChartView: View {
    let checkIns: [CheckIn]
    let days: Int
    /// IANA timezone of the receiver, so weekly buckets and average times align
    /// with the receiver's day, not the owner's device timezone.
    var timezone: String? = nil

    private let chartHeight: CGFloat = 160
    // Axis/label text scales with Dynamic Type instead of a fixed 9pt (US-IOS105).
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 9

    var body: some View {
        // Compute the buckets and bounds ONCE per body evaluation. These were
        // previously read ~10x per render (dataPoints + yMin/yMax/yMid/
        // overall*), each filtering/reducing the full check-in history.
        let calendar = Calendar.forTimezone(timezone)
        let firsts = Self.firstCheckInMinutes(checkIns: checkIns, days: days, calendar: calendar)
        let points = Self.computeDataPoints(firsts: firsts, days: days, calendar: calendar)
        let avgs = points.map(\.avgMinutes)
        let yMinV = max(0, (avgs.min() ?? 0) - 60)
        let yMaxV = min(1440, (avgs.max() ?? 1440) + 60)
        let yMidV = (yMinV + yMaxV) / 2
        let rawMinutes = firsts.map { $0.minutes }
        let overallAvgV = rawMinutes.isEmpty ? 0 : Double(rawMinutes.reduce(0, +)) / Double(rawMinutes.count)
        // Earliest / latest are real days, not the min/max of weekly averages.
        let overallMinV = rawMinutes.min() ?? 0
        let overallMaxV = rawMinutes.max() ?? 0
        let format: (Double) -> String = { Self.formatMinutes(Int($0), calendar: calendar) }

        return VStack(alignment: .leading, spacing: 12) {
            Text("First Check-In Time")
                .font(.headline)

            if points.isEmpty {
                Text("Not enough data to show a trend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: chartHeight)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 4) {
                    // Y-axis labels + chart area
                    HStack(alignment: .top, spacing: 4) {
                        // Y-axis labels
                        VStack {
                            Text(format(yMaxV))
                                .font(.system(size: labelSize))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(format(yMidV))
                                .font(.system(size: labelSize))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(format(yMinV))
                                .font(.system(size: labelSize))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 44, height: chartHeight)

                        // Chart
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let height = geometry.size.height

                            // Grid lines
                            Path { path in
                                for i in 0...4 {
                                    let y = height * CGFloat(i) / 4
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: width, y: y))
                                }
                            }
                            .stroke(Color(.systemGray5), lineWidth: 0.5)

                            // Trend line
                            Path { path in
                                for (index, point) in points.enumerated() {
                                    let x = width * CGFloat(index) / CGFloat(max(1, points.count - 1))
                                    let normalizedY = (point.avgMinutes - yMinV) / max(1, yMaxV - yMinV)
                                    let y = height - (height * CGFloat(normalizedY))

                                    if index == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                            // Data points
                            ForEach(0..<points.count, id: \.self) { index in
                                let point = points[index]
                                let x = width * CGFloat(index) / CGFloat(max(1, points.count - 1))
                                let normalizedY = (point.avgMinutes - yMinV) / max(1, yMaxV - yMinV)
                                let y = height - (height * CGFloat(normalizedY))

                                Circle()
                                    .fill(point.count > 0 ? Color.green : Color.clear)
                                    .frame(width: 6, height: 6)
                                    .position(x: x, y: y)
                                    .accessibilityLabel("\(point.label): usually \(format(point.avgMinutes)), \(point.count) day\(point.count == 1 ? "" : "s")")
                            }
                        }
                        .frame(height: chartHeight)
                    }

                    // X-axis labels
                    HStack {
                        Spacer().frame(width: 48)
                        if let first = points.first, let last = points.last {
                            Text(first.label)
                                .font(.system(size: labelSize))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if points.count > 2 {
                                let mid = points[points.count / 2]
                                Text(mid.label)
                                    .font(.system(size: labelSize))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            Text(last.label)
                                .font(.system(size: labelSize))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Summary stats
                HStack(spacing: 20) {
                    trendStat(label: "Usually", value: format(overallAvgV))
                    trendStat(label: "Earliest", value: format(Double(overallMinV)))
                    trendStat(label: "Latest", value: format(Double(overallMaxV)))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("First check-in of the day: usually \(format(overallAvgV)), earliest \(format(Double(overallMinV))), latest \(format(Double(overallMaxV))).")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level2)
    }

    // MARK: - Data Processing

    private struct DataPoint {
        let label: String
        let avgMinutes: Double
        let count: Int
    }

    /// The first check-in of each receiver-local day in the window, as
    /// minutes after that day's midnight.
    nonisolated static func firstCheckInMinutes(checkIns: [CheckIn], days: Int, calendar: Calendar, now: Date = Date()) -> [(day: Date, minutes: Int)] {
        let window = HistoryTimeline.window(days: days, now: now, calendar: calendar)
        var firstByDay: [Date: Date] = [:]
        for ci in checkIns where ci.checkedInAt >= window.start && ci.checkedInAt < window.end {
            let day = calendar.startOfDay(for: ci.checkedInAt)
            if let existing = firstByDay[day], existing <= ci.checkedInAt { continue }
            firstByDay[day] = ci.checkedInAt
        }
        let result = firstByDay.map { entry -> (day: Date, minutes: Int) in
            let c = calendar.dateComponents([.hour, .minute], from: entry.value)
            return (day: entry.key, minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        return result.sorted { $0.day < $1.day }
    }

    nonisolated private static func computeDataPoints(firsts: [(day: Date, minutes: Int)], days: Int, calendar: Calendar, now: Date = Date()) -> [DataPoint] {
        // Anchor the window to END today: exactly `days` days ending today
        // (the same window as the heatmap), so the most recent days are never
        // dropped from the chart.
        let window = HistoryTimeline.window(days: days, now: now, calendar: calendar)
        let windowStart = window.start
        let endExclusive = window.end

        // Group days by day (week views) or week (longer ranges).
        let bucketSize = days <= 7 ? 1 : 7
        // Ceiling so a range that isn't a whole multiple of the bucket size still
        // covers its most recent (partial) bucket.
        let bucketCount = Int((Double(days) / Double(bucketSize)).rounded(.up))

        var points: [DataPoint] = []
        // Locale-aware axis labels: weekday for week views, month/day otherwise (US-IOS044).
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate(days <= 7 ? "EEE" : "Md")
        dateFormatter.timeZone = calendar.timeZone

        for bucket in 0..<bucketCount {
            guard let bucketStart = calendar.date(byAdding: .day, value: bucket * bucketSize, to: windowStart) else {
                continue
            }
            let rawEnd = calendar.date(byAdding: .day, value: bucketSize, to: bucketStart) ?? endExclusive
            let bucketEnd = min(rawEnd, endExclusive)

            let bucketDays = firsts.filter { $0.day >= bucketStart && $0.day < bucketEnd }
            if bucketDays.isEmpty { continue }

            let avg = Double(bucketDays.reduce(0) { $0 + $1.minutes }) / Double(bucketDays.count)
            points.append(DataPoint(
                label: dateFormatter.string(from: bucketStart),
                avgMinutes: avg,
                count: bucketDays.count
            ))
        }

        return points
    }

    // MARK: - Formatting

    /// Minutes-after-midnight as a short time in the reader's locale (12- or
    /// 24-hour) — the hand-built "h:mm AM/PM" ignored 24-hour readers, the
    /// same bug the PDF's averageCheckInTime fixed.
    nonisolated static func formatMinutes(_ totalMinutes: Int, calendar: Calendar, locale: Locale = .current) -> String {
        let clamped = max(0, min(1439, totalMinutes))
        var components = DateComponents()
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = clamped / 60
        components.minute = clamped % 60
        guard let date = calendar.date(from: components) else { return "—" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func trendStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
