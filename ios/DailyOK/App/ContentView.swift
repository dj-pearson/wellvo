import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @StateObject private var forceUpdate = ForceUpdateState.shared
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        ZStack {
            Group {
                switch authViewModel.authState {
                case .loading:
                    LaunchScreenView()
                case .unauthenticated:
                    AuthView()
                case .authenticated:
                    // Only honor an invite/auto-join deep link when the user isn't
                    // already a member, so a stray link can't demote an owner/viewer.
                    if let inviteToken = appState.pendingInviteToken, appState.currentUserRole == nil {
                        ReceiverOnboardingView(inviteToken: inviteToken)
                    } else if appState.pendingAutoJoin != nil, appState.currentUserRole == nil {
                        ReceiverOnboardingView(inviteToken: nil)
                    } else if appState.showPairingCodeEntry {
                        PairingCodeEntryView()
                    } else if appState.isOnboarding {
                        OnboardingView()
                    } else if appState.currentUserRole == .receiver {
                        ReceiverHomeView()
                    } else if appState.currentUserRole == .viewer {
                        ViewerTabView()
                    } else {
                        OwnerTabView()
                    }
                }
            }
            // Obscure all content behind the biometric lock so failing Face ID
            // genuinely withholds the account data (not just a cosmetic flag).
            if authViewModel.authState == .authenticated && authViewModel.biometricLocked {
                BiometricLockView()
                    .transition(.opacity)
            }
            // Hard block when a possible MITM is detected on this network.
            if appState.secureConnectionFailed {
                SecureConnectionBlockedView()
                    .transition(.opacity)
            }
            // Hard block when the backend says this build is too old to talk to it.
            if forceUpdate.required {
                ForceUpdateView(updateURL: forceUpdate.updateURL)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut, value: authViewModel.authState)
        .animation(reduceMotion ? nil : .easeInOut, value: authViewModel.biometricLocked)
        .onChange(of: authViewModel.authState) { newState in
            if newState == .unauthenticated {
                appState.currentUserRole = nil
            }
        }
        .task(id: authViewModel.authState) {
            // Resolve the role even when an invite/auto-join token is pending, so an
            // existing member who taps a link gets routed by role (not hijacked into
            // receiver onboarding). The auto-join probe still only runs for genuinely
            // new users with no pending token.
            guard authViewModel.authState == .authenticated,
                  appState.currentUserRole == nil else { return }

            // Keep `users.timezone` aligned with the device zone so the edge
            // function dedup and the owner dashboard's "today" window never
            // drift when the user travels or reinstalls.
            Task { await AuthService.shared.syncTimezoneIfChanged() }

            // Load the user's existing role from the DB first.
            // This ensures receivers/viewers are routed correctly on every login,
            // not just after the initial onboarding flow.
            if let role = await FamilyService.shared.getCurrentUserRole() {
                appState.currentUserRole = role
                // Already a member: drop any stale invite/auto-join deep link so it
                // can't surface the receiver onboarding flow over their real home.
                appState.pendingInviteToken = nil
                appState.pendingAutoJoin = nil
                return
            }

            // No existing membership — check for phone-based auto-join (new user),
            // unless we're already handling a token-based invite.
            guard appState.pendingInviteToken == nil, appState.pendingAutoJoin == nil else { return }
            do {
                if let result = try await FamilyService.shared.checkAutoJoin() {
                    appState.pendingAutoJoin = result
                }
            } catch {
                // Auto-join is best-effort; don't block the user
            }
        }
    }
}

/// Full-screen lock shown while `biometricLocked`. Obscures account data and
/// offers a retry. The session is genuinely withheld from out-of-process
/// surfaces while this is up (see `AuthViewModel.checkBiometricOnResume`), so
/// this is real protection, not a cosmetic overlay.
struct BiometricLockView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Daily OK is locked")
                    .font(.title2.weight(.semibold))
                Text("Unlock to access your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    guard !isAuthenticating else { return }
                    isAuthenticating = true
                    Task {
                        await authViewModel.attemptBiometricUnlock()
                        isAuthenticating = false
                    }
                } label: {
                    Text(isAuthenticating ? "Unlocking…" : "Unlock")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isAuthenticating)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
            .padding()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily OK is locked. Unlock to access your account.")
        }
    }
}

/// Hard block shown when the launch probe detects a genuine certificate
/// mismatch — a device-trusted but un-pinned CA, i.e. a likely MITM. No content
/// is reachable behind it; the user must move to a trusted network.
struct SecureConnectionBlockedView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Secure connection couldn't be verified")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Daily OK won't send your information over this network because its security couldn't be confirmed. This can happen on some public Wi-Fi or with a monitoring profile installed. Switch to a trusted network or cellular and reopen the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding()
            .accessibilityElement(children: .combine)
        }
    }
}

/// Blocking screen shown when the backend rejects this build as below
/// `MIN_SUPPORTED_IOS_APP_VERSION`. There's no dismiss — the only path forward
/// is updating, so the app can't hit an API contract it no longer satisfies.
struct ForceUpdateView: View {
    let updateURL: URL?
    @Environment(\.openURL) private var openURL

    /// Never leave the only CTA dead: if both the server URL and the bundled
    /// App Store URL failed to parse, fall back to an App Store search so the
    /// user can always reach an update.
    private var effectiveURL: URL {
        updateURL ?? URL(string: "https://apps.apple.com/search?term=Daily%20OK")!
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Update Daily OK")
                    .font(.title2.weight(.semibold))
                Text("This version of Daily OK is no longer supported. Please update to the latest version to keep your family's check-ins working.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    openURL(effectiveURL)
                } label: {
                    Text("Update Now")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
            .padding()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Update required. This version of Daily OK is no longer supported. Update now.")
        }
    }
}

struct LaunchScreenView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var heartSize: CGFloat = 80

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: heartSize))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Daily OK heart icon")
                Text("Daily OK")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityLabel("Daily OK")
                ProgressView()
                    .accessibilityLabel("Loading")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily OK is loading")
        }
    }
}
