import WidgetKit
import SwiftUI
import AppIntents

/// Receiver one-tap check-in widget for Home Screen and Lock Screen. The button
/// runs the shared `CheckInIntent` in place (iOS 17 interactive widgets), so the
/// receiver never has to open the app — ideal for seniors.
struct CheckInWidget: Widget {
    let kind = "DailyOKCheckInWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CheckInProvider()) { entry in
            CheckInWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Check-In")
        .description("Tap “I'm OK” to let your family know — from your Home or Lock Screen.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

private let brandGreen = Color(red: 0.133, green: 0.773, blue: 0.369)

struct CheckInWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CheckInEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            default: home
            }
        }
        // When not signed in — or locked (tokens withheld) — tapping opens the
        // app to finish setup / unlock. Only a fully-ready surface stays inert.
        .widgetURL((entry.isSignedIn && !entry.isLocked) ? nil : URL(string: "dailyok://checkin"))
    }

    // MARK: Home Screen (small / medium)

    @ViewBuilder private var home: some View {
        if !entry.isSignedIn {
            VStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill").font(.title).foregroundStyle(brandGreen)
                Text("Open Daily OK").font(.caption).fontWeight(.semibold)
                Text("to finish setup").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(homeAccessibilityLabel)
        } else if entry.hasCheckedInToday {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(brandGreen)
                Text("You're all set!").font(.headline)
                if let at = entry.lastCheckInAt {
                    Text("Checked in \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(homeAccessibilityLabel)
        } else if entry.isLocked {
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.title).foregroundStyle(.secondary)
                Text("Tap to unlock").font(.caption).fontWeight(.semibold)
                Text("and check in").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(homeAccessibilityLabel)
        } else {
            VStack(spacing: 10) {
                Button(intent: CheckInIntent(source: "widget")) {
                    Label("I'm OK", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(brandGreen)
                .accessibilityLabel("I'm OK, check in")
                .accessibilityHint("Lets your family know you're OK today.")
                Text("Tap to let your family know")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    /// VoiceOver description of the current state for the Home Screen variant.
    private var homeAccessibilityLabel: String {
        if !entry.isSignedIn { return "Daily OK. Open the app to finish setup." }
        if entry.isLocked { return "Daily OK is locked. Activate to open the app and unlock to check in." }
        if entry.hasCheckedInToday {
            if let at = entry.lastCheckInAt {
                return "Checked in today at \(at.formatted(date: .omitted, time: .shortened))."
            }
            return "Checked in today."
        }
        return "You haven't checked in today. Activate to check in and let your family know you're OK."
    }

    // MARK: Lock Screen accessories

    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.hasCheckedInToday {
                Image(systemName: "checkmark.circle.fill").font(.title2)
            } else if entry.isLocked {
                Image(systemName: "lock.fill").font(.title3)
            } else {
                Button(intent: CheckInIntent(source: "widget")) {
                    Image(systemName: "hand.tap.fill").font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .widgetAccentable()
        .accessibilityLabel(entry.hasCheckedInToday ? "Checked in today" : (entry.isLocked ? "Locked. Tap to unlock." : "Tap to check in"))
    }

    @ViewBuilder private var inline: some View {
        if entry.hasCheckedInToday {
            Label("Checked in", systemImage: "checkmark.circle.fill")
        } else if entry.isLocked {
            Label("Unlock to check in", systemImage: "lock.fill")
        } else {
            Label("Tap to check in", systemImage: "hand.tap.fill")
        }
    }

    @ViewBuilder private var rectangular: some View {
        if entry.hasCheckedInToday {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.title2)
                VStack(alignment: .leading) {
                    Text("You're all set").font(.headline)
                    if let at = entry.lastCheckInAt {
                        Text(at.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        } else if entry.isLocked {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text("Locked").font(.headline)
                    Text("Tap to unlock").font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            Button(intent: CheckInIntent(source: "widget")) {
                Label("I'm OK", systemImage: "checkmark.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
