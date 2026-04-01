import SwiftUI
import AuthenticationServices

// MARK: - Password Strength

enum PasswordStrength: Int, Comparable {
    case weak = 0, fair, good, strong

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        }
    }

    var color: Color {
        switch self {
        case .weak: return .red
        case .fair: return .orange
        case .good: return .yellow
        case .strong: return .green
        }
    }

    var progress: Double {
        switch self {
        case .weak: return 0.25
        case .fair: return 0.5
        case .good: return 0.75
        case .strong: return 1.0
        }
    }

    static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .weak }

        var score = 0

        // Length
        if password.count >= 10 { score += 1 }
        if password.count >= 14 { score += 1 }

        // Character diversity
        if password.contains(where: { $0.isUppercase }) { score += 1 }
        if password.contains(where: { $0.isLowercase }) { score += 1 }
        if password.contains(where: { $0.isNumber }) { score += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { score += 1 }

        // Penalty for common patterns
        let commonPasswords: Set<String> = [
            "password", "123456789", "1234567890", "qwerty1234", "iloveyou1",
            "password1", "password12", "password123",
        ]
        if commonPasswords.contains(password.lowercased()) { return .weak }

        switch score {
        case 0...2: return .weak
        case 3: return .fair
        case 4...5: return .good
        default: return .strong
        }
    }
}

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
                // Password strength indicator
                if !authViewModel.password.isEmpty {
                    let strength = PasswordStrength.evaluate(authViewModel.password)
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(strength.color)
                                    .frame(width: geo.size.width * strength.progress, height: 4)
                                    .animation(.easeInOut(duration: 0.2), value: strength)
                            }
                        }
                        .frame(height: 4)
                        HStack {
                            Text(strength.label)
                                .font(.caption2)
                                .foregroundStyle(strength.color)
                            Spacer()
                        }
                    }
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
