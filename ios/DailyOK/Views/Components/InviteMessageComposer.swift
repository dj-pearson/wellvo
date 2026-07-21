import SwiftUI
import MessageUI

/// Presents the native iOS Messages composer, prefilled with an invite, so the
/// text is sent from the **owner's own phone number** rather than our Twilio
/// A2P number. An invite goes to someone who hasn't opted into our A2P 10DLC
/// campaign, so it can't be delivered by the approved sender; sending it P2P
/// from the owner's device sidesteps A2P entirely. The Twilio campaign is
/// reserved for escalation alerts.
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

    func body(content: Content) -> some View {
        content.sheet(item: $item) { invite in
            Group {
                if InviteMessageComposer.canSendText {
                    InviteMessageComposer(invite: invite) { sent in
                        item = nil
                        onFinish(sent)
                    }
                } else {
                    InviteShareSheet(text: invite.message) { completed in
                        item = nil
                        onFinish(completed)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}
