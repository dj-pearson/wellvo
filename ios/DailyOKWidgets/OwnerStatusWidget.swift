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
    case "pending": return .yellow
    case "missed": return .red
    default: return .gray
    }
}

private func icon(for status: String) -> String {
    switch status {
    case "checked_in": return "checkmark.circle.fill"
    case "pending": return "clock.fill"
    case "missed": return "exclamationmark.circle.fill"
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

    @ViewBuilder private func accessory(_ s: SharedOwnerState) -> some View {
        HStack(spacing: 6) {
            Image(systemName: s.checkedInCount(asOf: now) == s.total ? "checkmark.circle.fill" : "person.2.fill")
            VStack(alignment: .leading) {
                Text("Family check-ins").font(.headline)
                Text(summaryText(s)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func small(_ s: SharedOwnerState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryText(s)).font(.caption).fontWeight(.semibold)
            if let r = s.mostRelevant(asOf: now) {
                let status = r.status(asOf: now)
                HStack(spacing: 6) {
                    Image(systemName: icon(for: status)).foregroundStyle(color(for: status))
                    Text(r.name).font(.subheadline).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func list(_ s: SharedOwnerState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryText(s)).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            ForEach(s.receivers.prefix(family == .systemLarge ? 8 : 3)) { r in
                let status = r.status(asOf: now)
                HStack(spacing: 8) {
                    Image(systemName: icon(for: status)).foregroundStyle(color(for: status))
                    Text(r.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    // A bare time — "8:15 AM" — reads as today. Only show it
                    // when it IS today; otherwise the status word carries the
                    // truth.
                    if status == "checked_in", let at = r.lastCheckIn(asOf: now) {
                        Text(at.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(label(for: status)).font(.caption2).foregroundStyle(color(for: status))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func label(for status: String) -> String {
        switch status {
        case "pending": return "Pending"
        case "missed": return "Missed"
        case "no_data": return "—"
        default: return ""
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2.fill").font(.title3).foregroundStyle(.secondary)
            Text("Open Daily OK").font(.caption).fontWeight(.semibold)
        }
    }
}
