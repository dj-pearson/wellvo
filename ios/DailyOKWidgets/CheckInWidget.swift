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
/// Help state. Orange rather than red: it says "sent, your family knows", not
/// "something failed".
private let helpOrange = Color(red: 0.90, green: 0.45, blue: 0.05)

struct CheckInWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CheckInEntry

    /// The one state this entry is in, in priority order. A help request
    /// outranks "done"; "done" outranks everything that would offer the button.
    private enum Mode {
        case setup, help(String), done, locked, saved, failed(String), due

        var isSaved: Bool {
            if case .saved = self { return true }
            return false
        }
    }

    private var mode: Mode {
        if !entry.isSignedIn { return .setup }
        if let kind = entry.helpKind { return .help(kind) }
        // Saved-but-not-sent outranks "done": a queued tap is not "all set".
        if entry.pendingSend { return entry.isLocked ? .locked : .saved }
        if entry.hasCheckedInToday { return .done }
        if entry.isLocked { return .locked }
        if let message = entry.failureMessage { return .failed(message) }
        return .due
    }

    /// Whether a tap anywhere on the widget should open the app. The due and
    /// saved states keep their button instead.
    private var opensApp: Bool {
        switch mode {
        case .setup, .locked, .failed, .help: return true
        case .done, .saved, .due: return false
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            default: home
            }
        }
        .widgetURL(opensApp ? URL(string: "dailyok://checkin") : nil)
    }

    private func helpTitle(_ kind: String) -> String {
        kind == "call_me" ? "Call requested" : "Help requested"
    }

    private func helpLine(_ kind: String) -> String {
        let who = entry.ownerName ?? "your family"
        return kind == "call_me" ? "We asked \(who) to call you" : "We told \(who) you need help"
    }

    /// "Due at 9:00 AM" when the next check-in is later today, or the family is
    /// asking again; otherwise the plain prompt.
    private var dueLine: String {
        if entry.askedAgain { return "Your family is asking again" }
        if let next = entry.nextCheckInAt, next > entry.date {
            var cal = Calendar.current
            cal.timeZone = entry.timeZone
            if cal.isDate(next, inSameDayAs: entry.date) {
                return "Due at \(entry.timeText(next))"
            }
        }
        return "Tap to let your family know"
    }

    /// "Next: tomorrow 9:00 AM" under "You're all set".
    private var nextLine: String? {
        guard let next = entry.nextCheckInAt, next > entry.date else { return nil }
        var cal = Calendar.current
        cal.timeZone = entry.timeZone
        let day = cal.isDate(next, inSameDayAs: entry.date) ? "today" : (cal.isDateInTomorrow(next) ? "tomorrow" : "")
        return day.isEmpty ? "Next: \(entry.timeText(next))" : "Next: \(day) \(entry.timeText(next))"
    }

    private var checkInButtonLabel: some View {
        Label("I'm OK", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    // MARK: Home Screen (small / medium)

    @ViewBuilder private var home: some View {
        switch mode {
        case .setup:
            VStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill").font(.title).foregroundStyle(brandGreen)
                Text("Open Daily OK").font(.caption).fontWeight(.semibold)
                Text("to finish setup").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(homeAccessibilityLabel)
        case .help(let kind):
            VStack(spacing: 6) {
                Image(systemName: kind == "call_me" ? "phone.arrow.down.left.fill" : "exclamationmark.bubble.fill")
                    .font(.title).foregroundStyle(helpOrange)
                Text(helpTitle(kind)).font(.headline)
                Text(helpLine(kind)).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2)
                if let at = entry.helpAt {
                    Text("Sent \(entry.timeText(at))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(homeAccessibilityLabel)
        case .done:
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(brandGreen)
                Text("You're all set!").font(.headline)
                if let at = entry.lastCheckInAt {
                    Text("Checked in \(entry.timeText(at))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let nextLine {
                    Text(nextLine).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(homeAccessibilityLabel)
        case .locked:
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.title).foregroundStyle(.secondary)
                Text("Tap to unlock").font(.caption).fontWeight(.semibold)
                Text("and check in").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(homeAccessibilityLabel)
        case .saved:
            VStack(spacing: 8) {
                Label("Saved on this iPhone", systemImage: "clock.fill")
                    .font(.caption).fontWeight(.semibold)
                Text("It will send when Daily OK can be reached.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(intent: CheckInIntent(source: "widget")) {
                    Text("Send now").font(.caption).fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(brandGreen)
                .accessibilityHint("Tries to send your saved check-in again.")
            }
            .padding(.horizontal, 4)
        case .failed(let message):
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(helpOrange)
                Text("Didn't send").font(.caption).fontWeight(.semibold)
                Text(message).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(3).multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(homeAccessibilityLabel)
        case .due:
            VStack(spacing: 10) {
                Button(intent: CheckInIntent(source: "widget")) {
                    checkInButtonLabel
                }
                .buttonStyle(.borderedProminent)
                .tint(brandGreen)
                .accessibilityLabel("I'm OK, check in")
                .accessibilityHint("Lets your family know you're OK today.")
                Text(dueLine)
                    .font(.caption2).foregroundStyle(.secondary)
                    // Replaced by the system's pending state while the tap runs.
                    .invalidatableContent()
            }
            .padding(.horizontal, 4)
        }
    }

    /// VoiceOver description of the current state for the Home Screen variant.
    private var homeAccessibilityLabel: String {
        switch mode {
        case .setup: return "Daily OK. Open the app to finish setup."
        case .locked: return "Daily OK is locked. Activate to open the app and unlock to check in."
        case .help(let kind):
            return "\(helpTitle(kind)). \(helpLine(kind))."
        case .done:
            if let at = entry.lastCheckInAt {
                return "Checked in today at \(entry.timeText(at))."
            }
            return "Checked in today."
        case .saved: return "Your check-in is saved on this iPhone and will send when Daily OK can be reached."
        case .failed(let message): return "Your check-in didn't send. \(message) Activate to open Daily OK."
        case .due: return "You haven't checked in today. Activate to check in and let your family know you're OK."
        }
    }

    // MARK: Lock Screen accessories

    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch mode {
            case .setup: Image(systemName: "heart.text.square").font(.title3)
            case .help: Image(systemName: "exclamationmark.bubble.fill").font(.title3)
            case .done: Image(systemName: "checkmark.circle.fill").font(.title2)
            case .locked: Image(systemName: "lock.fill").font(.title3)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.title3)
            case .saved, .due:
                Button(intent: CheckInIntent(source: "widget")) {
                    Image(systemName: mode.isSaved ? "clock.fill" : "hand.tap.fill").font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .widgetAccentable()
        .accessibilityLabel(accessoryAccessibilityLabel)
    }

    private var accessoryAccessibilityLabel: String {
        switch mode {
        case .setup: return "Daily OK. Open the app to finish setup."
        case .help(let kind): return helpTitle(kind)
        case .done: return "Checked in today"
        case .locked: return "Locked. Tap to unlock."
        case .saved: return "Check-in saved, not sent yet. Tap to send now."
        case .failed: return "Check-in didn't send. Tap to open Daily OK."
        case .due: return "Tap to check in"
        }
    }

    @ViewBuilder private var inline: some View {
        switch mode {
        case .setup: Label("Open Daily OK", systemImage: "heart.text.square")
        case .help(let kind): Label(helpTitle(kind), systemImage: "exclamationmark.bubble.fill")
        case .done: Label("Checked in", systemImage: "checkmark.circle.fill")
        case .locked: Label("Unlock to check in", systemImage: "lock.fill")
        case .saved: Label("Check-in saved", systemImage: "clock.fill")
        case .failed: Label("Didn't send", systemImage: "exclamationmark.triangle.fill")
        case .due: Label("Tap to check in", systemImage: "hand.tap.fill")
        }
    }

    @ViewBuilder private var rectangular: some View {
        switch mode {
        case .setup:
            accessoryRow(icon: "heart.text.square", title: "Open Daily OK", detail: "to finish setup")
        case .help(let kind):
            accessoryRow(icon: "exclamationmark.bubble.fill", title: helpTitle(kind), detail: entry.helpAt.map { "Sent \(entry.timeText($0))" })
        case .done:
            accessoryRow(icon: "checkmark.circle.fill", title: "You're all set", detail: entry.lastCheckInAt.map { entry.timeText($0) })
        case .locked:
            accessoryRow(icon: "lock.fill", title: "Locked", detail: "Tap to unlock")
        case .failed:
            accessoryRow(icon: "exclamationmark.triangle.fill", title: "Didn't send", detail: "Tap to open Daily OK")
        case .saved:
            Button(intent: CheckInIntent(source: "widget")) {
                accessoryRow(icon: "clock.fill", title: "Saved", detail: "Tap to send now")
            }
            .buttonStyle(.plain)
        case .due:
            Button(intent: CheckInIntent(source: "widget")) {
                Label("I'm OK", systemImage: "checkmark.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func accessoryRow(icon: String, title: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.title2)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
