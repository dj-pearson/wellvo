import SwiftUI
import PDFKit

/// Generates a PDF report of check-in history for sharing with
/// healthcare providers or family meetings.
@MainActor
struct CheckInReportGenerator {

    struct ReportData {
        let receiverName: String
        let familyName: String
        let checkIns: [CheckIn]
        let periodDays: Int
        let generatedAt: Date
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
                .foregroundColor: UIColor.label,
            ]
            let title = "Wellvo Check-In Report"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttrs)
            yPosition += 36

            // Subtitle
            let subtitleFont = UIFont.systemFont(ofSize: 14)
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: UIColor.secondaryLabel,
            ]
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long

            let subtitle = "\(data.receiverName) — \(data.familyName)"
            subtitle.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttrs)
            yPosition += 22

            let periodEnd = dateFormatter.string(from: data.generatedAt)
            let periodStart = dateFormatter.string(from:
                Calendar.current.date(byAdding: .day, value: -data.periodDays, to: data.generatedAt) ?? data.generatedAt
            )
            let period = "Period: \(periodStart) — \(periodEnd)"
            period.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttrs)
            yPosition += 30

            // Divider
            drawLine(in: context.cgContext, from: CGPoint(x: margin, y: yPosition), to: CGPoint(x: pageWidth - margin, y: yPosition))
            yPosition += 16

            // Summary stats
            let calendar = Calendar.current
            let totalDays = data.periodDays
            let totalCheckIns = data.checkIns.count
            let consistency = totalDays > 0 ? Double(totalCheckIns) / Double(totalDays) * 100 : 0

            let sectionFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
            let sectionAttrs: [NSAttributedString.Key: Any] = [.font: sectionFont, .foregroundColor: UIColor.label]
            let bodyFont = UIFont.systemFont(ofSize: 12)
            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.label]

            "Summary".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionAttrs)
            yPosition += 24

            let summaryLines = [
                "Total Check-Ins: \(totalCheckIns) / \(totalDays) days",
                "Consistency: \(String(format: "%.0f", consistency))%",
                "Average Check-In Time: \(averageCheckInTime(data.checkIns))",
                "Mood Breakdown: \(moodBreakdownString(data.checkIns))",
            ]

            for line in summaryLines {
                line.draw(at: CGPoint(x: margin + 16, y: yPosition), withAttributes: bodyAttrs)
                yPosition += 18
            }
            yPosition += 12

            // Streak info
            let streak = calculateStreak(data.checkIns)
            "Current Streak: \(streak) day(s)".draw(at: CGPoint(x: margin + 16, y: yPosition), withAttributes: bodyAttrs)
            yPosition += 24

            drawLine(in: context.cgContext, from: CGPoint(x: margin, y: yPosition), to: CGPoint(x: pageWidth - margin, y: yPosition))
            yPosition += 16

            // Daily log table header
            "Daily Log".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionAttrs)
            yPosition += 24

            // Table header
            let headerFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.secondaryLabel,
            ]

            let columns: [(String, CGFloat)] = [
                ("Date", margin),
                ("Time", margin + contentWidth * 0.35),
                ("Source", margin + contentWidth * 0.6),
                ("Mood", margin + contentWidth * 0.8),
            ]

            for (label, x) in columns {
                label.draw(at: CGPoint(x: x, y: yPosition), withAttributes: headerAttrs)
            }
            yPosition += 16

            drawLine(in: context.cgContext, from: CGPoint(x: margin, y: yPosition), to: CGPoint(x: pageWidth - margin, y: yPosition), color: UIColor.separator)
            yPosition += 6

            // Table rows
            let rowFont = UIFont.systemFont(ofSize: 10)
            let rowAttrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: UIColor.label]

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "MMM d, yyyy"
            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "h:mm a"

            for checkIn in data.checkIns.sorted(by: { $0.checkedInAt > $1.checkedInAt }) {
                if yPosition > pageHeight - margin - 30 {
                    // New page
                    context.beginPage()
                    yPosition = margin
                }

                let dateStr = dateFmt.string(from: checkIn.checkedInAt)
                let timeStr = timeFmt.string(from: checkIn.checkedInAt)
                let sourceStr = checkIn.source.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
                let moodStr: String
                switch checkIn.mood {
                case .happy: moodStr = "Good"
                case .neutral: moodStr = "Okay"
                case .tired: moodStr = "Tired"
                case .none: moodStr = "—"
                }

                dateStr.draw(at: CGPoint(x: columns[0].1, y: yPosition), withAttributes: rowAttrs)
                timeStr.draw(at: CGPoint(x: columns[1].1, y: yPosition), withAttributes: rowAttrs)
                sourceStr.draw(at: CGPoint(x: columns[2].1, y: yPosition), withAttributes: rowAttrs)
                moodStr.draw(at: CGPoint(x: columns[3].1, y: yPosition), withAttributes: rowAttrs)
                yPosition += 16
            }

            // Footer
            yPosition = pageHeight - margin
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.tertiaryLabel,
            ]
            let footer = "Generated by Wellvo on \(dateFormatter.string(from: data.generatedAt)) — wellvo.net"
            footer.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: footerAttrs)
        }

        return pdfData
    }

    // MARK: - Helpers

    private static func drawLine(in context: CGContext, from: CGPoint, to: CGPoint, color: UIColor = .separator) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.5)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
    }

    private static func averageCheckInTime(_ checkIns: [CheckIn]) -> String {
        guard !checkIns.isEmpty else { return "—" }
        let calendar = Calendar.current
        let totalMinutes = checkIns.reduce(0) { sum, ci in
            let c = calendar.dateComponents([.hour, .minute], from: ci.checkedInAt)
            return sum + (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let avg = totalMinutes / checkIns.count
        let h = avg / 60
        let m = avg % 60
        let period = h >= 12 ? "PM" : "AM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(displayH):\(String(format: "%02d", m)) \(period)"
    }

    private static func moodBreakdownString(_ checkIns: [CheckIn]) -> String {
        var counts: [String: Int] = [:]
        for ci in checkIns {
            switch ci.mood {
            case .happy: counts["Good", default: 0] += 1
            case .neutral: counts["Okay", default: 0] += 1
            case .tired: counts["Tired", default: 0] += 1
            case .none: break
            }
        }
        if counts.isEmpty { return "No mood data" }
        return counts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }

    private static func calculateStreak(_ checkIns: [CheckIn]) -> Int {
        guard !checkIns.isEmpty else { return 0 }
        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())
        let checkInDays = Set(checkIns.map { calendar.startOfDay(for: $0.checkedInAt) })

        while checkInDays.contains(currentDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
            currentDate = prev
        }
        return streak
    }
}
