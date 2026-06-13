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
                    Text(context.state.status == "missed" ? "Missed" : "Overdue")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(brandOrange)
                }
                Text("Waiting since \(context.state.dueSince, style: .time) · \(context.state.dueSince, style: .relative)")
                    .font(.caption2).foregroundStyle(.secondary)
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
                    Text(context.state.status == "missed" ? "Missed" : "Overdue")
                        .font(.caption).foregroundStyle(brandOrange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.dueSince, style: .relative)
                        .font(.caption2).foregroundStyle(.secondary)
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
                Text(context.state.dueSince, style: .timer).frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(brandOrange)
            }
            .widgetURL(standDownURL(receiverId: context.attributes.receiverId, familyId: context.attributes.familyId))
        }
    }
}
