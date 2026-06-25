import WidgetKit
import SwiftUI
import ActivityKit

private let brandOrange = Color(red: 0.976, green: 0.451, blue: 0.086)

private func dialURL(_ phone: String?) -> URL? {
    guard let phone else { return nil }
    let number = String(phone.filter { "+0123456789".contains($0) })
    return number.isEmpty ? nil : URL(string: "tel://\(number)")
}

private func standDownURL(receiverId: String, familyId: String) -> URL {
    URL(string: "dailyok://standdown?receiver=\(receiverId)&family=\(familyId)")!
}

/// Status word, suffixed once ActivityKit marks the activity stale (the 6h
/// `staleDate` set in EscalationActivityManager). Past that point the resolution
/// state can no longer be trusted, so the surface should read as "stuck" rather
/// than keep an ever-growing live timer running at the owner's most anxious
/// moment (US-IOS127).
private func statusText(_ context: ActivityViewContext<EscalationActivityAttributes>) -> String {
    let base = context.state.status == "missed" ? "Missed" : "Overdue"
    return context.isStale ? "\(base) 6h+" : base
}

/// Owner Live Activity during a missed/escalating check-in. Turns the most
/// anxious moment into a calm, trackable, actionable surface on the Lock Screen
/// and in the Dynamic Island.
struct EscalationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EscalationActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(context.attributes.receiverName, systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.headline)
                    Spacer()
                    Text(statusText(context))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(brandOrange)
                }
                if context.isStale {
                    Text("Waiting since \(context.state.dueSince, style: .time) · over 6h ago")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Waiting since \(context.state.dueSince, style: .time) · \(context.state.dueSince, style: .relative)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if let url = dialURL(context.attributes.receiverPhone) {
                        Link(destination: url) {
                            Label("Call now", systemImage: "phone.fill").font(.caption).fontWeight(.semibold)
                        }
                    }
                    Spacer()
                    Link(destination: standDownURL(receiverId: context.attributes.receiverId, familyId: context.attributes.familyId)) {
                        Label("Stand down", systemImage: "hand.raised.fill").font(.caption)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.5))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.receiverName, systemImage: "person.fill")
                        .font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(statusText(context))
                        .font(.caption).foregroundStyle(brandOrange)
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.isStale {
                        Text("Overdue 6h+").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(context.state.dueSince, style: .relative)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let url = dialURL(context.attributes.receiverPhone) {
                            Link(destination: url) { Label("Call", systemImage: "phone.fill") }
                        }
                        Spacer()
                        Link(destination: standDownURL(receiverId: context.attributes.receiverId, familyId: context.attributes.familyId)) {
                            Label("Stand down", systemImage: "hand.raised.fill")
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(brandOrange)
            } compactTrailing: {
                // Once stale, stop the unbounded counting timer — show a static
                // "stuck" glyph instead so it doesn't alarm indefinitely.
                if context.isStale {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(brandOrange)
                } else {
                    Text(context.state.dueSince, style: .timer).frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(brandOrange)
            }
            .widgetURL(standDownURL(receiverId: context.attributes.receiverId, familyId: context.attributes.familyId))
        }
    }
}
