import SwiftUI

/// The entire watch experience: one giant "I'm OK" button. Deliberately minimal
/// for senior receivers — one tap, clear haptic + visual confirmation.
struct WatchCheckInView: View {
    @StateObject private var model = WatchCheckInModel()
    @StateObject private var connectivity = WatchConnectivityProvider.shared
    @Environment(\.scenePhase) private var scenePhase

    private let brandGreen = Color(red: 0.133, green: 0.773, blue: 0.369)

    var body: some View {
        Group {
            if !model.isSignedIn {
                notSignedIn
            } else if model.didCheckIn {
                allSet
            } else {
                checkInButton
            }
        }
        .onAppear { model.reload() }
        // A fresh snapshot from the phone arrived — re-read it.
        .onChange(of: connectivity.revision) { _, _ in model.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
    }

    private var checkInButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await model.checkIn() }
            } label: {
                ZStack {
                    Circle().fill(brandGreen)
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
            }
            .buttonStyle(.plain)
            .disabled(model.isCheckingIn)
            .accessibilityLabel("Check in and let your family know you're okay")

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else {
                Text("Tap to check in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var allSet: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(brandGreen)
            Text("You're all set!")
                .font(.headline)
            if let at = model.state?.lastCheckInAt {
                Text("Checked in \(at.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checked in. Your family has been notified.")
    }

    private var notSignedIn: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2)
                .foregroundStyle(brandGreen)
            Text("Open Daily OK on your iPhone and sign in to check in from your watch.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }
}
