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
                action(title: "Call", systemImage: "phone.fill", tint: DailyOKColor.green600, urlString: "tel://\(number)")
                action(title: "FaceTime", systemImage: "video.fill", tint: .blue, urlString: "facetime://\(number)")
                action(title: "Text", systemImage: "message.fill", tint: .indigo, urlString: "sms:\(number)")
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func action(title: String, systemImage: String, tint: Color, urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.title3)
                    Text(title)
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .glassPill(style: .thin)
                .foregroundStyle(tint)
            }
            .accessibilityLabel("\(title) \(name)")
        }
    }
}
