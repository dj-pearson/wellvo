import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @StateObject private var forceUpdate = ForceUpdateState.shared
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

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
                    } else if appState.currentUserRole == .owner {
                        OwnerTabView()
                    } else if appState.roleResolution == .failed {
                        // No role, and we could not find out. Never guess — an
                        // owner dashboard shown to a receiver is the failure
                        // this replaces.
                        RoleLoadFailedView { Task { await resolveRole() } }
                    } else if appState.roleResolution == .resolved {
                        // Signed in, genuinely no family: ask, don't assume owner.
                        GetStartedChoiceView()
                    } else {
                        LaunchScreenView()
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
            // Topmost, and deliberately not animated: this exists to be in place
            // when iOS takes the App Switcher snapshot, which happens during the
            // `.inactive` window. A transition would let the real UI be captured
            // mid-fade, which is the leak it is here to prevent.
            if appState.privacyCoverActive {
                PrivacyCoverView()
            }
        }
        // The result of an action taken from a deep link (today: the escalation
        // Live Activity's "Stand down"). Presented at the root because the link
        // can arrive over any screen, and on a cold start over none of them yet.
        .alert(
            appState.deepLinkOutcome?.title ?? "",
            isPresented: Binding(
                get: { appState.deepLinkOutcome != nil },
                set: { if !$0 { appState.deepLinkOutcome = nil } }
            ),
            presenting: appState.deepLinkOutcome
        ) { _ in
            Button("OK", role: .cancel) { appState.deepLinkOutcome = nil }
        } message: { outcome in
            Text(outcome.message)
        }
        .animation(reduceMotion ? nil : .easeInOut, value: authViewModel.authState)
        .animation(reduceMotion ? nil : .easeInOut, value: authViewModel.biometricLocked)
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.showDashboardRequested)) { _ in
            // "View Details" on a location / low-battery / missed-check-in
            // notification. The action already brings the app forward; this
            // decides where it lands.
            appState.selectedTab = .dashboard
        }
        .onChange(of: authViewModel.authState) { newState in
            if newState == .unauthenticated {
                appState.currentUserRole = nil
                appState.roleResolution = .resolving
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A lookup that failed (offline launch) is retried when the app
            // comes back, instead of only on the next cold start.
            if phase == .active, authViewModel.authState == .authenticated,
               appState.roleResolution == .failed {
                Task { await resolveRole() }
            }
        }
        .onChange(of: appState.currentUserRole) { _, role in
            // Keep the offline cache in step with every role change (joining,
            // finishing owner setup, transferring ownership).
            Task {
                guard let userId = try? await SupabaseService.shared.client.auth.session.user.id else { return }
                appState.cacheRole(role, for: userId)
            }
        }
        .task(id: authViewModel.authState) {
            guard authViewModel.authState == .authenticated,
                  appState.currentUserRole == nil else { return }

            // Keep `users.timezone` aligned with the device zone so the edge
            // function dedup, the owner dashboard's "today" window and (since
            // 00052) the receiver's scheduled prompts never drift.
            Task { await AuthService.shared.syncTimezoneIfChanged() }

            await resolveRole()
        }
    }

    /// Work out where this signed-in user belongs.
    ///
    /// 1. Show the last known role at once (offline launches open the right app).
    /// 2. Ask the server. A failure keeps the cached role, or — with none —
    ///    shows a retry screen; it never falls through to owner screens.
    /// 3. With no membership, try a phone-number invite match before asking the
    ///    user what they're here to do.
    private func resolveRole() async {
        guard let userId = try? await SupabaseService.shared.client.auth.session.user.id else { return }

        if appState.currentUserRole == nil, let cached = appState.cachedRole(for: userId) {
            appState.currentUserRole = cached
        }
        appState.roleResolution = .resolving

        let role: UserRole?
        do {
            role = try await FamilyService.shared.getCurrentUserRole()
        } catch {
            appState.roleResolution = .failed
            return
        }

        if let role {
            appState.currentUserRole = role
            // Already a member: drop any stale invite/auto-join deep link so it
            // can't surface the receiver onboarding flow over their real home.
            appState.pendingInviteToken = nil
            appState.pendingAutoJoin = nil
            appState.roleResolution = .resolved
            return
        }

        // The server says: no family. A cached role from a removed membership
        // must not keep them in an app they no longer belong to.
        appState.currentUserRole = nil

        // No membership — check for a phone-number invite match (new user),
        // unless an invite link is already being handled.
        if appState.pendingInviteToken == nil, appState.pendingAutoJoin == nil {
            if let result = try? await FamilyService.shared.checkAutoJoin() {
                appState.pendingAutoJoin = result
            }
        }
        appState.roleResolution = .resolved
    }
}

/// Shown when a signed-in user's role can't be loaded and none is cached.
private struct RoleLoadFailedView: View {
    let retry: () -> Void

    var body: some View {
        ZStack {
            AmbientBackground(tone: .neutral)
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Can't reach Daily OK")
                    .font(.title2.weight(.bold))
                Text("Check your internet connection. We'll try again when you come back to the app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(DailyOKColor.green500)
                    .controlSize(.large)
            }
            .padding(32)
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

/// What the App Switcher shows instead of a family's data when the user relies
/// on biometric lock. Opaque, static, and carrying no account information.
struct PrivacyCoverView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var heartSize: CGFloat = 80

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: heartSize))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Daily OK")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily OK is locked")
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
