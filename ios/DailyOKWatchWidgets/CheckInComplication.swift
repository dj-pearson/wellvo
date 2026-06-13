import WidgetKit
import SwiftUI

/// Watch-face complication: an always-visible check-in status. A filled green
/// check means "done today"; an open ring means "tap to check in". Tapping the
/// complication launches the watch app (its giant button completes the check-in).
struct CheckInComplication: Widget {
    let kind = "DailyOKCheckInComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Daily Check-In")
        .description("See today's status and tap to check in.")
        .supportedFamilies([
            .accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular,
        ])
    }
}

private let brandGreen = Color(red: 0.133, green: 0.773, blue: 0.369)

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var icon: String {
        entry.hasCheckedInToday ? "checkmark.circle.fill" : "hand.tap.fill"
    }
    private var text: String {
        guard entry.isSignedIn else { return "Sign in" }
        return entry.hasCheckedInToday ? "Checked in" : "Check in"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(text, systemImage: icon)
        case .accessoryCorner:
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(brandGreen)
                .widgetLabel(text)
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(brandGreen)
                VStack(alignment: .leading) {
                    Text(entry.hasCheckedInToday ? "You're all set" : "Tap to check in")
                        .font(.headline)
                    if let at = entry.lastCheckInAt, entry.hasCheckedInToday {
                        Text(at.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        default: // accessoryCircular
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(entry.hasCheckedInToday ? brandGreen : .primary)
            }
            .widgetAccentable()
            .accessibilityLabel(text)
        }
    }
}
