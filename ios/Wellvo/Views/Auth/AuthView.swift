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
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 80

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo & Tagline
                VStack(spacing: 12) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: logoSize))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

                    Text("Wellvo")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    Text("One tap. Total peace of mind.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showEmailAuth {
                    emailAuthSection
                } else {
                    phoneAuthSection
                }

                // Toggle between phone and email
                Button {
                    if reduceMotion {
                        showEmailAuth.toggle()
                        authViewModel.errorMessage = nil
                    } else {
                        withAnimation {
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
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                Spacer()

                // iPad / alternate-device setup via pairing code
                Button {
                    joinViaCode = true
                } label: {
                    Label("Have a setup code?", systemImage: "number.square")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: authViewModel.errorMessage)
            .onChange(of: authViewModel.authState) { newState in
                if newState == .authenticated, joinViaCode {
                    appState.showPairingCodeEntry = true
                    joinViaCode = false
                }
            }
        }
    }

    // MARK: - Phone Auth (Primary — simplest for receivers)

    private var phoneAuthSection: some View {
        VStack(spacing: 16) {
            if authViewModel.isAwaitingOTP {
                // Step 2: Enter the code
                Text("Enter the code we texted you")
                    .font(.headline)

                TextField("6-digit code", text: $authViewModel.otpCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospaced())
                    .frame(maxWidth: 200)
                    .onSubmit { Task { await authViewModel.verifyPhoneOTP() } }

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
                .disabled(authViewModel.isLoading)

                Button("Use a different number") {
                    authViewModel.isAwaitingOTP = false
                    authViewModel.otpCode = ""
                    authViewModel.errorMessage = nil
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .disabled(authViewModel.isLoading)

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
            }

            TextField("Email", text: $authViewModel.email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)

            SecureField("Password", text: $authViewModel.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(isSignUp ? .newPassword : .password)
                .submitLabel(.go)
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
                Text("Password must be 8+ characters with uppercase, lowercase, and a number.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            .disabled(authViewModel.isLoading)

            Button {
                if reduceMotion {
                    isSignUp.toggle()
                    authViewModel.errorMessage = nil
                } else {
                    withAnimation {
                        isSignUp.toggle()
                        authViewModel.errorMessage = nil
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
