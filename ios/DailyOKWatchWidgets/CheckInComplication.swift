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
private let brandAmber = Color(red: 0.96, green: 0.62, blue: 0.04)
private let brandOrange = Color(red: 0.95, green: 0.45, blue: 0.10)

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var icon: String {
        if entry.helpKind != nil { return "exclamationmark.bubble.fill" }
        // Saved-not-sent outranks done: a queued tap is not "all set".
        if entry.isQueued { return "clock.badge.checkmark" }
        return entry.hasCheckedInToday ? "checkmark.circle.fill" : "circle.dashed"
    }
    private var text: String {
        guard entry.isSignedIn else { return "Sign in" }
        if entry.helpKind != nil { return "Help sent" }
        if entry.isQueued { return "Saved" }
        return entry.hasCheckedInToday ? "Checked in" : "Check in"
    }
    /// Green when done (or saved), orange for a help request, open amber when
    /// a check-in is due.
    private var tint: Color {
        guard entry.isSignedIn else { return .secondary }
        if entry.helpKind != nil { return brandOrange }
        return (entry.hasCheckedInToday || entry.isQueued) ? brandGreen : brandAmber
    }
    private var headline: String {
        if entry.helpKind != nil { return entry.helpKind == "call_me" ? "Call requested" : "Help requested" }
        if entry.isQueued { return "Saved, not sent" }
        return entry.hasCheckedInToday ? "You're all set" : "Tap to check in"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(text, systemImage: icon)
        case .accessoryCorner:
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .widgetLabel(text)
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                VStack(alignment: .leading) {
                    Text(headline)
                        .font(.headline)
                    if entry.isQueued {
                        Text("Sends when connected")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if let at = entry.lastCheckInAt, entry.hasCheckedInToday {
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
                    .foregroundStyle(tint)
            }
            .widgetAccentable()
            .accessibilityLabel(text)
        }
    }
}
