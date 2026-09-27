import SwiftUI

/// The entire watch experience: one giant "I'm OK" button. Deliberately minimal
/// for senior receivers — one tap, clear haptic + visual confirmation.
struct WatchCheckInView: View {
    @StateObject private var model = WatchCheckInModel()
    @StateObject private var connectivity = WatchConnectivityProvider.shared
    @Environment(\.scenePhase) private var scenePhase

    private let brandGreen = Color(red: 0.133, green: 0.773, blue: 0.369)
    private let brandGradient = LinearGradient(
        colors: [Color(red: 0.157, green: 0.82, blue: 0.42),
                 Color(red: 0.086, green: 0.64, blue: 0.29)],
        startPoint: .top,
        endPoint: .bottom
    )

    private let helpOrange = Color(red: 0.95, green: 0.55, blue: 0.15)
    @State private var showHelpChoices = false

    var body: some View {
        Group {
            if !model.isSignedIn {
                notSignedIn
            } else if let kind = model.helpKind {
                helpSent(kind)
            } else if model.didCheckIn {
                allSet
            } else {
                checkInButton
            }
        }
        // Need help / call me from the wrist, confirmed first (a wrist tap is
        // easy to make by accident). Offered from every signed-in state: the
        // moment it matters is rarely the moment a check-in is due.
        .confirmationDialog("Ask for help?", isPresented: $showHelpChoices, titleVisibility: .visible) {
            Button("I need help", role: .destructive) {
                Task { await model.sendHelp("need_help") }
            }
            Button("Ask \(model.ownerName ?? "my family") to call me") {
                Task { await model.sendHelp("call_me") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.ownerName ?? "Your family") will be alerted right away.")
        }
        .onAppear {
            model.reload()
            Task { await model.syncPendingIfNeeded() }
        }
        // A fresh snapshot from the phone arrived (often a reconnect) — re-read
        // it and try to flush any queued check-in.
        .onChange(of: connectivity.revision) { _, _ in
            model.reload()
            Task { await model.syncPendingIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reload()
                Task { await model.syncPendingIfNeeded() }
            }
        }
    }

    private var checkInButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await model.checkIn() }
            } label: {
                ZStack {
                    Circle().fill(brandGradient)
                    if model.isCheckingIn {
                        ProgressView().tint(.white)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "hand.tap.fill").font(.title2)
                            Text("I'm OK").font(.headline)
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(model.isCheckingIn)
            .accessibilityLabel("Check in and let your family know you're okay")

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Tap to check in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            helpButton
        }
        .padding(.horizontal, 4)
    }

    private var helpButton: some View {
        Button {
            showHelpChoices = true
        } label: {
            if model.isSendingHelp {
                ProgressView()
            } else {
                Label("Need help?", systemImage: "exclamationmark.bubble.fill")
                    .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .tint(helpOrange)
        .disabled(model.isSendingHelp)
        .accessibilityHint("Asks your family for help or for a call.")
    }

    private func helpSent(_ kind: String) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: kind == "call_me" ? "phone.arrow.down.left.fill" : "exclamationmark.bubble.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(helpOrange)
                Text(WatchHelpCopy.sent(kind, ownerName: model.ownerName))
                    .font(.headline)
                if let at = model.state?.helpAt {
                    Text("Sent \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("If you can, call them too.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }

    private var allSet: some View {
        ScrollView {
            VStack(spacing: 8) {
                VStack(spacing: 8) {
                    Image(systemName: model.queued ? "clock.badge.checkmark" : "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(brandGreen)
                    Text(model.queued ? "Saved, not sent yet" : "You're all set!")
                        .font(.headline)
                    if model.queued {
                        Text("It will send when your watch or iPhone is connected.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let at = model.state?.lastCheckInAt {
                        Text("Checked in \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                // VoiceOver used to hear "Your family has been notified" for a
                // tap that was only saved on the watch.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.queued
                    ? "Saved, not sent yet. It will send when your watch or iPhone is connected."
                    : "Checked in. Your family has been notified.")
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption2)
                }
                helpButton
            }
            .multilineTextAlignment(.center)
        }
    }

    private var notSignedIn: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2)
                .foregroundStyle(brandGreen)
            Text(model.removedMessage ?? "Open Daily OK on your iPhone and sign in to check in from your watch.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }
}
