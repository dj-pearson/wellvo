import SwiftUI
import MessageUI

/// Presents the native iOS Messages composer, prefilled with an invite, so the
/// text is sent from the **owner's own phone number**. Daily OK's servers send
/// no text messages at all (server SMS needs an A2P 10DLC registration); every
/// text between family members — invites here, "Text Mom" on the dashboard,
/// "Text Sarah" on the receiver's help card — is written in the phone's own
/// Messages composer, pre-filled, and sent person to person.
///
/// The invite record is created on the backend *before* this is presented, so
/// phone-based auto-join works whenever the receiver eventually signs in — this
/// controller is only the delivery step.
struct InviteMessageComposer: UIViewControllerRepresentable {
    let invite: InviteDetails
    /// Called when the composer finishes. `sent` is true only when the user
    /// actually sent the message (not on cancel or failure).
    let onFinish: (_ sent: Bool) -> Void

    /// Whether this device can send SMS/iMessage at all (false on most iPads,
    /// the Simulator, and iPod touch). Callers fall back to the share sheet.
    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = [invite.phone]
        controller.body = invite.message
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            // Let the parent clear its `.sheet(item:)` binding to dismiss; don't
            // dismiss here or the two paths race.
            onFinish(result == .sent)
        }
    }
}

/// Share-sheet fallback for devices that can't send SMS. Lets the owner deliver
/// the invite text via any share target (Mail, WhatsApp, AirDrop, Copy, …).
struct InviteShareSheet: UIViewControllerRepresentable {
    let text: String
    /// `completed` reflects the standard `UIActivityViewController` completion
    /// (true when the user actually finished a share action).
    let onFinish: (_ completed: Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            context.coordinator.onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
    }
}

extension View {
    /// Present the native invite composer (or share-sheet fallback) for the
    /// bound `InviteDetails`. Clears the binding on finish and reports whether
    /// the invite was actually sent so the caller can advance its flow.
    func inviteComposer(
        item: Binding<InviteDetails?>,
        onFinish: @escaping (_ sent: Bool) -> Void
    ) -> some View {
        modifier(InviteComposerModifier(item: item, onFinish: onFinish))
    }
}

private struct InviteComposerModifier: ViewModifier {
    @Binding var item: InviteDetails?
    let onFinish: (Bool) -> Void
    /// Set when the composer / share sheet reported its own result. Swiping
    /// the sheet down skips those callbacks; onDismiss then reports "not sent"
    /// so the caller never sits there without knowing what happened.
    @State private var controllerReported = false

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: {
            if !controllerReported { onFinish(false) }
            controllerReported = false
        }) { invite in
            Group {
                if InviteMessageComposer.canSendText {
                    InviteMessageComposer(invite: invite) { sent in
                        controllerReported = true
                        item = nil
                        onFinish(sent)
                    }
                } else {
                    InviteShareSheet(text: invite.message) { completed in
                        controllerReported = true
                        item = nil
                        onFinish(completed)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Family texts ("Text Mom")

/// A pre-filled text for the phone's own Messages app. Nothing is sent by
/// Daily OK: the person reviews it and taps Send themselves.
struct TextMessageDraft: Identifiable, Equatable {
    let id = UUID()
    /// Recipient number as stored (the composer / sms: URL normalizes).
    let recipient: String
    let body: String

    /// `sms:` fallback for a device where the composer isn't available. iOS
    /// takes the body after `&body=`. Nil when there's nothing dialable.
    var smsURL: URL? {
        guard let number = ContactQuickActions.dialableNumber(recipient) else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+#")
        let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "sms:\(number)&body=\(encoded)")
    }
}

/// The Messages composer for a `TextMessageDraft`.
struct TextMessageComposer: UIViewControllerRepresentable {
    let draft: TextMessageDraft
    let onFinish: (_ sent: Bool) -> Void

    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = [draft.recipient]
        controller.body = draft.body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> InviteMessageComposer.Coordinator {
        InviteMessageComposer.Coordinator(onFinish: onFinish)
    }
}

extension View {
    /// Open the bound draft in Messages: the in-app composer when this device
    /// can send texts, else the Messages app via `sms:`, else the share sheet
    /// (so the words can still go out another way). Clears the binding.
    func textMessageComposer(item: Binding<TextMessageDraft?>) -> some View {
        modifier(TextMessageComposerModifier(item: item))
    }
}

private struct TextMessageComposerModifier: ViewModifier {
    @Binding var item: TextMessageDraft?

    private struct Presented: Identifiable {
        let draft: TextMessageDraft
        let useComposer: Bool
        var id: UUID { draft.id }
    }
    @State private var presented: Presented?

    func body(content: Content) -> some View {
        content
            .onChange(of: item) { _, draft in
                guard let draft else { return }
                item = nil
                if TextMessageComposer.canSendText {
                    presented = Presented(draft: draft, useComposer: true)
                } else if let url = draft.smsURL {
                    Task { @MainActor in
                        let opened = await UIApplication.shared.open(url)
                        if !opened { presented = Presented(draft: draft, useComposer: false) }
                    }
                } else {
                    presented = Presented(draft: draft, useComposer: false)
                }
            }
            .sheet(item: $presented) { shown in
                Group {
                    if shown.useComposer {
                        TextMessageComposer(draft: shown.draft) { _ in presented = nil }
                    } else {
                        InviteShareSheet(text: shown.draft.body) { _ in presented = nil }
                    }
                }
                .ignoresSafeArea()
            }
    }
}

/// Short, warm pre-filled bodies for family texts. Pure, so they're testable.
enum FamilyTextMessage {
    /// "Margaret Smith" → "Margaret". Falls back to the whole name.
    static func greetingName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    /// Caregiver → receiver, from the dashboard card or an alert's "Text"
    /// action. Nil when the card isn't asking for anything (checked in, not
    /// due yet, no data).
    static func checkingOn(name: String, status: ReceiverCheckInStatus, helpKind: HelpKind?) -> String? {
        let first = greetingName(name)
        let hi = first.isEmpty ? String(localized: "Hi") : String(localized: "Hi \(first)")
        switch status {
        case .needsHelp:
            if helpKind == .callMe {
                return String(localized: "\(hi), I saw you'd like a call. I'll ring you in a minute. Keep your phone close.")
            }
            return String(localized: "\(hi), I got your help alert and I'm on it. Are you OK? Call or text me back if you can.")
        case .missed:
            return String(localized: "\(hi), I didn't get your Daily OK check-in today and just want to make sure you're OK. Can you text me back?")
        case .pending:
            return String(localized: "\(hi), just checking in. I haven't seen your Daily OK tap yet. All good?")
        case .checkedIn, .noData, .upcoming:
            return nil
        }
    }

    /// Receiver → owner, from the help card: says what they need and, when
    /// the phone already had a fix, roughly where they are (about 100 m).
    static func askingForHelp(kind: ReceiverHelpKind, ownerName: String?, location: CheckInLocation?) -> String {
        let hi = ownerName.map { String(localized: "Hi \(greetingName($0)), ") } ?? ""
        var body: String
        switch kind {
        case .callMe:
            body = hi + String(localized: "can you call me as soon as you can?")
        case .pickMeUp:
            body = hi + String(localized: "can you come and pick me up?")
        case .stayLonger:
            body = hi + String(localized: "can I stay a little longer?")
        case .needHelp, .sos:
            body = hi + String(localized: "I need help. Please call me as soon as you can.")
        }
        if hi.isEmpty, let firstChar = body.first {
            body = firstChar.uppercased() + body.dropFirst()
        }
        if let link = approximateMapLink(location) {
            body += "\n" + String(localized: "I'm around here: \(link)")
        }
        return body
    }

    /// Apple Maps link rounded to 3 decimals (~100 m): enough to find someone,
    /// no more precise than it needs to be.
    static func approximateMapLink(_ location: CheckInLocation?) -> String? {
        guard let location,
              location.latitude.isFinite, location.longitude.isFinite,
              abs(location.latitude) <= 90, abs(location.longitude) <= 180,
              !(location.latitude == 0 && location.longitude == 0)
        else { return nil }
        let ll = String(format: "%.3f,%.3f", location.latitude, location.longitude)
        return "https://maps.apple.com/?ll=\(ll)"
    }
}
