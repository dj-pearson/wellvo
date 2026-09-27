import WidgetKit
import SwiftUI

/// Owner peace-of-mind widget: every receiver's check-in status at a glance,
/// without opening the app. Tapping deep-links into the dashboard.
struct OwnerStatusWidget: Widget {
    let kind = "DailyOKOwnerStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OwnerStatusProvider()) { entry in
            OwnerStatusView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "dailyok://dashboard"))
        }
        .configurationDisplayName("Family Status")
        .description("See who has checked in today, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

private func color(for status: String) -> Color {
    switch status {
    case "checked_in": return .green
    // Orange, not yellow: plain yellow is close to unreadable on a light
    // widget background (the app switched to deep amber for the same reason).
    case "pending": return .orange
    case "missed", "needs_help": return .red
    default: return .gray
    }
}

private func icon(for status: String, helpKind: String? = nil) -> String {
    switch status {
    case "checked_in": return "checkmark.circle.fill"
    case "pending": return "clock.fill"
    case "missed": return "exclamationmark.circle.fill"
    case "stood_down": return "hand.raised.fill"
    case "needs_help":
        switch helpKind {
        case "call_me": return "phone.arrow.down.left.fill"
        case "sos": return "sos"
        default: return "exclamationmark.bubble.fill"
        }
    case "upcoming": return "calendar.badge.clock"
    default: return "minus.circle.fill"
    }
}

struct OwnerStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OwnerStatusEntry

    /// Everything below reads status as of the ENTRY's date, not as of the
    /// moment the snapshot was written. Only the phone app writes that snapshot,
    /// so an owner who has not opened the app since yesterday would otherwise
    /// see yesterday's green ticks — a stale "checked in" is the false
    /// reassurance the whole product exists to prevent.
    private var now: Date { entry.date }

    var body: some View {
        if let state = entry.state, !state.receivers.isEmpty {
            switch family {
            case .accessoryRectangular: accessory(state)
            case .systemSmall: small(state)
            default: list(state)
            }
        } else {
            empty
        }
    }

    private func summaryText(_ s: SharedOwnerState) -> String {
        "\(s.checkedInCount(asOf: now)) of \(s.total) checked in"
    }

    /// Lock Screen: who needs the owner, by name, when someone does. The count
    /// alone read the same on a slow morning and on the morning Mom asked for
    /// help. Names are privacy-sensitive: redacted when the owner hides widget
    /// data on the locked Lock Screen.
    @ViewBuilder private func accessory(_ s: SharedOwnerState) -> some View {
        let headline = s.headline(asOf: now)
        HStack(spacing: 6) {
            Image(systemName: headline != nil
                  ? "exclamationmark.circle.fill"
                  : (s.checkedInCount(asOf: now) == s.total ? "checkmark.circle.fill" : "person.2.fill"))
            VStack(alignment: .leading) {
                if let headline {
                    Text(headline).font(.headline).lineLimit(2).privacySensitive()
                } else {
                    Text("Family check-ins").font(.headline)
                }
                Text(summaryText(s)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func small(_ s: SharedOwnerState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryText(s)).font(.caption).fontWeight(.semibold)
            if let r = s.mostRelevant(asOf: now) {
                let status = r.status(asOf: now)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: status, helpKind: r.helpKind)).foregroundStyle(color(for: status))
                        Text(r.name).font(.subheadline).lineLimit(1)
                    }
                    // The status in words, not just a coloured symbol: VoiceOver
                    // users and anyone who can't tell red from orange got only
                    // "Mom" here.
                    Text(rowDetail(r, status: status))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                .privacySensitive()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.name), \(rowDetail(r, status: status)). \(summaryText(s)).")
            }
            Spacer(minLength: 0)
            ageFootnote(s)
        }
    }

    /// "Checked in 8:15 AM", "Asked you to call · Tom is on it", "Alerts
    /// stopped", "Pending"…
    private func rowDetail(_ r: SharedOwnerReceiver, status: String) -> String {
        var text = r.label(forStatus: status)
        if status == "checked_in", let at = r.lastCheckIn(asOf: now) {
            text = "Checked in \(r.timeText(at))"
        }
        if (status == "needs_help" || status == "missed"), let who = r.claimedByName, !who.isEmpty {
            text += " · \(who) is on it"
        }
        return text
    }

    @ViewBuilder private func list(_ s: SharedOwnerState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryText(s)).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            ForEach(s.receivers.prefix(family == .systemLarge ? 8 : 3)) { r in
                let status = r.status(asOf: now)
                HStack(spacing: 8) {
                    Image(systemName: icon(for: status, helpKind: r.helpKind)).foregroundStyle(color(for: status))
                    Text(r.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    // A bare time — "8:15 AM" — reads as today. Only show it
                    // when it IS today; otherwise the status word carries the
                    // truth. The word is in the primary/secondary text colour:
                    // the icon carries the colour.
                    if status == "checked_in", let at = r.lastCheckIn(asOf: now) {
                        Text(r.timeText(at))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(rowDetail(r, status: status))
                            .font(.caption2)
                            .fontWeight(status == "needs_help" || status == "missed" ? .semibold : .regular)
                            .foregroundStyle(status == "needs_help" || status == "missed" ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
                .privacySensitive()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.name), \(rowDetail(r, status: status))")
            }
            Spacer(minLength: 0)
            ageFootnote(s)
        }
    }

    /// The snapshot only changes when the phone app runs. Say how old it is
    /// once that matters, so a status from hours ago isn't read as live.
    @ViewBuilder private func ageFootnote(_ s: SharedOwnerState) -> some View {
        if now.timeIntervalSince(s.updatedAt) >= 60 * 60 {
            Text("Updated \(s.updatedAt, style: .relative) ago")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Two different situations used to share a bare "Open Daily OK": nobody
    /// to check on yet, and no family on this phone (signed out, or this is
    /// the receiver's phone).
    @ViewBuilder private var empty: some View {
        let noReceivers = entry.state != nil
        VStack(spacing: 6) {
            Image(systemName: "person.2.fill").font(.title3).foregroundStyle(.secondary)
            Text(noReceivers ? "Add someone to check on" : "Open Daily OK")
                .font(.caption).fontWeight(.semibold).multilineTextAlignment(.center)
            if !noReceivers {
                Text("to see your family").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(noReceivers
            ? "Daily OK. Nobody to check on yet. Open the app to add someone."
            : "Daily OK. Open the app to see your family's check-ins.")
    }
}
