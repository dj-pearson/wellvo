import SwiftUI

/// One-tap Call / FaceTime / Message actions for reaching a receiver fast in the
/// moment something looks off. Renders nothing when no phone number is known.
/// Uses tel: / facetime: / sms: URL schemes — no backend; the number is already
/// on the user record.
struct ContactQuickActions: View {
    let name: String
    let phone: String?

    /// Keep only the dialable characters so a formatted number like
    /// "(555) 123-4567" still produces a valid tel: URL.
    private var dialable: String? {
        guard let phone else { return nil }
        let allowed = Set("+0123456789")
        let cleaned = String(phone.filter { allowed.contains($0) })
        return cleaned.isEmpty ? nil : cleaned
    }

    var body: some View {
        if let number = dialable {
            HStack(spacing: 10) {
                action(title: "Call", systemImage: "phone.fill", tint: DailyOKColor.green600, urlString: "tel:\(number)")
                action(title: "FaceTime", systemImage: "video.fill", tint: .blue, urlString: "facetime://\(number)")
                action(title: "Text", systemImage: "message.fill", tint: .indigo, urlString: "sms:\(number)")
            }
            .padding(.top, 2)
        } else {
            // Don't render a blank gap in an escalation moment — say so plainly
            // (US-IOS112).
            Label("No phone number on file", systemImage: "phone.badge.plus")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .accessibilityLabel("No phone number on file for \(name)")
        }
    }

    @ViewBuilder
    private func action(title: String, systemImage: String, tint: Color, urlString: String) -> some View {
        // Only offer an action this device can actually perform (e.g. FaceTime /
        // tel on an iPad with no SIM would silently no-op), and confirm with a
        // haptic only when the open succeeds (US-IOS112).
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            Button {
                UIApplication.shared.open(url) { success in
                    if success { DailyOKHaptics.light() }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.title3)
                    Text(title)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44) // comfortable tap target in an escalation moment
                .padding(.vertical, 8)
                .glassPill(style: .thin)
                .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) \(name)")
        }
    }
}
