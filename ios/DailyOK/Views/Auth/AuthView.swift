import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isSignUp = false
    @State private var showEmailAuth = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: AuthField?
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 80

    private enum AuthField: Hashable { case name, email, password }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(tone: .calm)

                // Scrolls, so the primary button is always reachable: at an
                // accessibility text size, or on sign-up with the keyboard up,
                // the fixed stack pushed "Create Account" off the screen. The
                // minHeight keeps the roomy centred layout when it all fits.
                GeometryReader { proxy in
                    ScrollView {
                        content
                            .frame(minHeight: proxy.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .onAppear { authViewModel.refreshLockoutState() }
            // .done is included deliberately: leaving it out makes the sheet
            // dismiss itself the instant the password is set, so the user never
            // sees the confirmation and cannot tell success from a silent close.
            .sheet(isPresented: Binding(
                get: { authViewModel.resetStage != .request },
                set: { presented in
                    guard !presented else { return }
                    // Swiping the confirmation away finishes like "Done";
                    // anywhere earlier it is a cancel.
                    if authViewModel.resetStage == .done {
                        Task { await authViewModel.finishPasswordReset() }
                    } else {
                        authViewModel.cancelPasswordReset()
                    }
                }
            )) {
                PasswordResetSheet(authViewModel: authViewModel)
            }
        }
    }

    /// Logo glow shrinks at accessibility sizes so the form gets the room.
    private var showsLogoGlow: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 40)

            // Logo & Tagline
            VStack(spacing: 12) {
                ZStack {
                    if showsLogoGlow {
                        Circle()
                            .fill(DailyOKColor.green300.opacity(0.4))
                            .frame(width: logoSize * 1.6, height: logoSize * 1.6)
                            .blur(radius: 24)
                    }
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 56 : logoSize))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DailyOKColor.green400, DailyOKColor.green600],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .accessibilityHidden(true)
                }

                Text("Daily OK")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                Text("One tap. Total peace of mind.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Context the person arrived with: an invite link they tapped, or
            // "Have a setup code?". Both only act after sign-in, so say so.
            if appState.pendingInviteToken != nil {
                contextNotice(
                    icon: "envelope.open.fill",
                    text: "You've been invited to Daily OK. Sign in with the phone number the invite was sent to, and we'll show you whose family it is before you join."
                )
            } else if appState.setupCodeAfterSignIn {
                contextNotice(
                    icon: "number.square",
                    text: "First, sign in or create your account. Then we'll ask for the 6-digit code from your invite.",
                    cancel: { appState.setupCodeAfterSignIn = false }
                )
            }

            Spacer(minLength: 12)

            VStack(spacing: 16) {
                if showEmailAuth {
                    emailAuthSection
                } else {
                    phoneAuthSection
                }

                Button {
                    if reduceMotion {
                        showEmailAuth.toggle()
                        authViewModel.errorMessage = nil
                    } else {
                        withAnimation(DailyOKMotion.smoothSpring) {
                            showEmailAuth.toggle()
                            authViewModel.errorMessage = nil
                        }
                    }
                } label: {
                    Text(showEmailAuth ? "Sign in with phone number instead" : "Sign in with email instead")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DailyOKColor.error)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .padding(24)
            .glassCard(style: .regular, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level4)
            // Announce inline auth errors to VoiceOver when they appear
            // (US-IOS105).
            .announce(authViewModel.errorMessage) { $0 }

            Spacer()

            // Joining with the code from an invite text (any device). Sign-in
            // comes first; the tap now says so and is remembered until then.
            if !appState.setupCodeAfterSignIn && appState.pendingInviteToken == nil {
                Button {
                    appState.setupCodeAfterSignIn = true
                } label: {
                    Label("Have a setup code?", systemImage: "number.square")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DailyOKColor.green700)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassPill(style: .ultraThin)
                }
                .accessibilityHint("Sign in first, then enter the code from your invite")
                .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: authViewModel.errorMessage)
    }

    private func contextNotice(icon: String, text: LocalizedStringKey, cancel: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DailyOKColor.green700)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let cancel {
                    Button("I don't have a code", action: cancel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DailyOKColor.green700)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusMedium, elevation: DailyOKElevation.level2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Phone Auth (Primary — simplest for receivers)

    /// Renders the lockout countdown so a locked-out user understands why Send /
    /// Verify do nothing, instead of tapping into the void (US-IOS103).
    @ViewBuilder
    private var lockoutNotice: some View {
        if let message = authViewModel.authLockoutMessage {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DailyOKColor.error)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var phoneAuthSection: some View {
        VStack(spacing: 16) {
            if authViewModel.isAwaitingOTP {
                // Step 2: Enter the code
                Text("Enter the code we texted you")
                    .font(.headline)

                SegmentedCodeField(code: $authViewModel.otpCode, length: 6) {
                    Task { await authViewModel.verifyPhoneOTP() }
                }

                Button {
                    Task { await authViewModel.verifyPhoneOTP() }
                } label: {
                    if authViewModel.isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Text("Verify")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(authViewModel.isLoading || authViewModel.authLockoutSecondsRemaining > 0)

                // Resend the code (with a cooldown) — previously the only escape
                // was "Use a different number" (US-IOS103).
                Button(authViewModel.otpResendCooldown > 0
                       ? "Resend code in \(authViewModel.otpResendCooldown)s"
                       : "Resend code") {
                    Task { await authViewModel.resendPhoneOTP() }
                }
                .font(.footnote)
                .disabled(authViewModel.otpResendCooldown > 0 || authViewModel.isLoading)

                Button("Use a different number") {
                    authViewModel.isAwaitingOTP = false
                    authViewModel.otpCode = ""
                    authViewModel.errorMessage = nil
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                lockoutNotice
            } else {
                // Step 1: Enter phone number
                Text("Sign in with your phone number")
                    .font(.headline)

                TextField("(555) 123-4567", text: $authViewModel.phoneNumber)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .accessibilityLabel("Phone number")
                    .onSubmit { Task { await authViewModel.sendPhoneOTP() } }

                Text("US numbers as usual. Outside the US, start with + and your country code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await authViewModel.sendPhoneOTP() }
                } label: {
                    if authViewModel.isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Text("Send Code")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(authViewModel.isLoading || authViewModel.authLockoutSecondsRemaining > 0)

                lockoutNotice

                // Apple sign-in as secondary option
                SignInWithAppleButton(.signIn) { request in
                    authViewModel.configureAppleSignInRequest(request)
                } onCompletion: { result in
                    Task { await authViewModel.signInWithApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Email Auth (Secondary — for owners / tech-savvy users)

    private var emailAuthSection: some View {
        VStack(spacing: 12) {
            // Sign in with Apple
            SignInWithAppleButton(
                isSignUp ? .signUp : .signIn
            ) { request in
                authViewModel.configureAppleSignInRequest(request)
            } onCompletion: { result in
                Task { await authViewModel.signInWithApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .cornerRadius(12)

            HStack {
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                Text("or").foregroundStyle(.secondary).font(.footnote)
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            }

            if isSignUp {
                TextField("Your Name", text: $authViewModel.displayName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = .email }
            }

            TextField("Email", text: $authViewModel.email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit { focusedField = .password }

            SecureField("Password", text: $authViewModel.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(isSignUp ? .newPassword : .password)
                .submitLabel(.go)
                .focused($focusedField, equals: .password)
                .onSubmit {
                    Task {
                        if isSignUp {
                            await authViewModel.signUpWithEmail()
                        } else {
                            await authViewModel.signInWithEmail()
                        }
                    }
                }

            if isSignUp {
                if !authViewModel.password.isEmpty {
                    PasswordStrengthIndicator(password: authViewModel.password)
                }

                Text("Password must be 10+ characters with uppercase, lowercase, and a number.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isSignUp {
                HStack {
                    Spacer()
                    Button {
                        Task { await authViewModel.sendPasswordReset() }
                    } label: {
                        if authViewModel.isResettingPassword {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Forgot Password?")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DailyOKColor.green700)
                        }
                    }
                    .disabled(authViewModel.isResettingPassword)
                }
            }

            if let resetMessage = authViewModel.resetPasswordMessage {
                Text(resetMessage)
                    .font(.caption)
                    .foregroundStyle(DailyOKColor.green700)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    if isSignUp {
                        await authViewModel.signUpWithEmail()
                    } else {
                        await authViewModel.signInWithEmail()
                    }
                }
            } label: {
                // minHeight, not a fixed height: at an accessibility text size a
                // `.semibold` label needs more than 44pt and a fixed frame clips
                // it. The people this app is built for are the ones most likely
                // to be running one.
                if authViewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                } else {
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            // On sign-up, enforce the exact policy the copy promises so the user
            // isn't shown "Good" and then rejected by the server.
            .disabled(authViewModel.isLoading
                      || (isSignUp && !authViewModel.passwordMeetsPolicy)
                      || authViewModel.authLockoutSecondsRemaining > 0)

            // The lockout is shared with phone sign-in; say why the button is
            // off instead of letting taps do nothing.
            lockoutNotice

            Button {
                if reduceMotion {
                    isSignUp.toggle()
                    authViewModel.errorMessage = nil
                    // Also clear the reset-password confirmation so it doesn't
                    // linger across the Sign In / Sign Up switch (US-IOS103).
                    authViewModel.resetPasswordMessage = nil
                } else {
                    withAnimation {
                        isSignUp.toggle()
                        authViewModel.errorMessage = nil
                        authViewModel.resetPasswordMessage = nil
                    }
                }
            } label: {
                Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Password Reset (code, not link)

/// Completes a password reset from the 6-digit code in the reset email.
///
/// This app cannot use the emailed LINK. GoTrue builds it against the Supabase
/// API host and redirects to an allow-listed app origin, but dailyok.net serves
/// marketing pages and has no auth callback route, so the link has nowhere to
/// land. The same email carries a 6-digit code, which needs no redirect, no
/// allow-list entry and no web page at all.
///
/// Lives in this file rather than its own because DailyOK.xcodeproj uses explicit
/// file references (objectVersion 56, no synchronized groups), so a new file
/// would have to be hand-registered in project.pbxproj in four places.
struct PasswordResetSheet: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch authViewModel.resetStage {
                case .enterCode:
                    codeStep
                case .setPassword:
                    passwordStep
                case .done:
                    doneStep
                case .request:
                    EmptyView()
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(authViewModel.resetStage == .done ? "Close" : "Cancel") {
                        if authViewModel.resetStage == .done {
                            // The password IS changed; closing signs them in.
                            Task { await authViewModel.finishPasswordReset() }
                        } else {
                            authViewModel.cancelPasswordReset()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var codeStep: some View {
        VStack(spacing: 16) {
            Text("Enter the 6-digit code we emailed you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Same component the phone OTP step uses, so the two code entries in
            // this app look and behave alike.
            SegmentedCodeField(code: $authViewModel.recoveryCode, length: 6) {
                Task { await authViewModel.verifyRecoveryCode() }
            }

            if let error = authViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await authViewModel.verifyRecoveryCode() }
            } label: {
                if authViewModel.isResettingPassword {
                    ProgressView().frame(maxWidth: .infinity).frame(minHeight: 44)
                } else {
                    Text("Verify Code")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(authViewModel.isResettingPassword
                      || authViewModel.recoveryCode.filter(\.isNumber).count != 6)
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 16) {
            Text("Choose a new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("New password", text: $authViewModel.newPassword)
                .textContentType(.newPassword)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            // States the policy the server enforces, so the user is not told
            // "saved" and then rejected.
            Text("At least 10 characters, with uppercase, lowercase and a number.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = authViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await authViewModel.submitNewPassword() }
            } label: {
                if authViewModel.isResettingPassword {
                    ProgressView().frame(maxWidth: .infinity).frame(minHeight: 44)
                } else {
                    Text("Set Password")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(authViewModel.isResettingPassword || authViewModel.newPassword.isEmpty)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(authViewModel.resetPasswordMessage ?? String(localized: "Password updated."))
                .multilineTextAlignment(.center)
            Button("Done") {
                // Leaving .done closes the sheet; the user is signed in with
                // the new password.
                Task { await authViewModel.finishPasswordReset() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
}
