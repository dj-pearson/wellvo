import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isSignUp = false
    @State private var showEmailAuth = false
    @State private var joinViaCode = false
    @FocusState private var focusedField: AuthField?
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 80

    private enum AuthField: Hashable { case name, email, password }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(tone: .calm)

                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // Logo & Tagline
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(DailyOKColor.green300.opacity(0.4))
                                .frame(width: logoSize * 1.6, height: logoSize * 1.6)
                                .blur(radius: 24)
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: logoSize))
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

                    // iPad / alternate-device setup via pairing code
                    Button {
                        joinViaCode = true
                    } label: {
                        Label("Have a setup code?", systemImage: "number.square")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DailyOKColor.green700)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassPill(style: .ultraThin)
                    }
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: authViewModel.errorMessage)
            }
            .onChange(of: authViewModel.authState) { newState in
                if newState == .authenticated, joinViaCode {
                    appState.showPairingCodeEntry = true
                    joinViaCode = false
                }
            }
            // .done is included deliberately: leaving it out makes the sheet
            // dismiss itself the instant the password is set, so the user never
            // sees the confirmation and cannot tell success from a silent close.
            .sheet(isPresented: Binding(
                get: { authViewModel.resetStage != .request },
                set: { if !$0 { authViewModel.cancelPasswordReset() } }
            )) {
                PasswordResetSheet(authViewModel: authViewModel)
            }
        }
    }

    // MARK: - Phone Auth (Primary — simplest for receivers)

    /// Renders the lockout countdown so a locked-out user understands why Send /
    /// Verify do nothing, instead of tapping into the void (US-IOS103).
    @ViewBuilder
    private var lockoutNotice: some View {
        if let message = authViewModel.authLockoutMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.orange)
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
                    .onSubmit { Task { await authViewModel.sendPhoneOTP() } }

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
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .disabled(authViewModel.isResettingPassword)
                }
            }

            if let resetMessage = authViewModel.resetPasswordMessage {
                Text(resetMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
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
                if authViewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                } else {
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            // On sign-up, enforce the exact policy the copy promises so the user
            // isn't shown "Good" and then rejected by the server.
            .disabled(authViewModel.isLoading || (isSignUp && !authViewModel.passwordMeetsPolicy))

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
                    Button("Cancel") {
                        authViewModel.cancelPasswordReset()
                        dismiss()
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
                    ProgressView().frame(maxWidth: .infinity).frame(height: 44)
                } else {
                    Text("Verify Code")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
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
                    ProgressView().frame(maxWidth: .infinity).frame(height: 44)
                } else {
                    Text("Set Password")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
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
                authViewModel.cancelPasswordReset()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
}
