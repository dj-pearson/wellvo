import SwiftUI

/// A trend line chart showing average check-in time over the selected period.
/// Uses native SwiftUI drawing — no external chart library needed.
struct CheckInTrendChartView: View {
    let checkIns: [CheckIn]
    let days: Int

    private let chartHeight: CGFloat = 160

    var body: some View {
        // Compute the buckets and bounds ONCE per body evaluation. These were
        // previously read ~10x per render (dataPoints + yMin/yMax/yMid/
        // overall*), each filtering/reducing the full check-in history.
        let points = Self.computeDataPoints(checkIns: checkIns, days: days)
        let avgs = points.map(\.avgMinutes)
        let yMinV = max(0, (avgs.min() ?? 0) - 60)
        let yMaxV = min(1440, (avgs.max() ?? 1440) + 60)
        let yMidV = (yMinV + yMaxV) / 2
        let overallAvgV = avgs.isEmpty ? 0 : avgs.reduce(0, +) / Double(avgs.count)
        let overallMinV = avgs.min() ?? 0
        let overallMaxV = avgs.max() ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Check-In Time Trend")
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
                            Text(formatHour(yMaxV))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatHour(yMidV))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatHour(yMinV))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 36, height: chartHeight)

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
                                    .accessibilityLabel("\(point.label): average check-in at \(formatMinutesToTime(Int(point.avgMinutes))), \(point.count) check-in\(point.count == 1 ? "" : "s")")
                            }
                        }
                        .frame(height: chartHeight)
                    }

                    // X-axis labels
                    HStack {
                        Spacer().frame(width: 40)
                        if let first = points.first, let last = points.last {
                            Text(first.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if points.count > 2 {
                                let mid = points[points.count / 2]
                                Text(mid.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            Text(last.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Summary stats
                HStack(spacing: 20) {
                    trendStat(
                        label: "Average",
                        value: formatMinutesToTime(Int(overallAvgV))
                    )
                    trendStat(
                        label: "Earliest",
                        value: formatMinutesToTime(Int(overallMinV))
                    )
                    trendStat(
                        label: "Latest",
                        value: formatMinutesToTime(Int(overallMaxV))
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Data Processing

    private struct DataPoint {
        let label: String
        let avgMinutes: Double
        let count: Int
    }

    private static func computeDataPoints(checkIns: [CheckIn], days: Int) -> [DataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Group check-ins by week
        let bucketSize = days <= 7 ? 1 : 7
        let bucketCount = max(1, days / bucketSize)

        var points: [DataPoint] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = days <= 7 ? "EEE" : "M/d"

        for bucket in 0..<bucketCount {
            guard let bucketStart = calendar.date(byAdding: .day, value: -(days - bucket * bucketSize), to: today),
                  let bucketEnd = calendar.date(byAdding: .day, value: bucketSize, to: bucketStart) else {
                continue
            }

            let bucketCheckIns = checkIns.filter { ci in
                ci.checkedInAt >= bucketStart && ci.checkedInAt < bucketEnd
            }

            if bucketCheckIns.isEmpty {
                continue
            }

            let totalMinutes = bucketCheckIns.reduce(0.0) { sum, ci in
                let components = calendar.dateComponents([.hour, .minute], from: ci.checkedInAt)
                return sum + Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }

            let avg = totalMinutes / Double(bucketCheckIns.count)
            points.append(DataPoint(
                label: dateFormatter.string(from: bucketStart),
                avgMinutes: avg,
                count: bucketCheckIns.count
            ))
        }

        return points
    }

    // MARK: - Formatting

    private func formatHour(_ minutes: Double) -> String {
        formatMinutesToTime(Int(minutes))
    }

    private func formatMinutesToTime(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        let period = h >= 12 ? "PM" : "AM"
        let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(displayHour):\(String(format: "%02d", m)) \(period)"
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
