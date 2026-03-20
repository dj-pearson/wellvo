import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isSignUp = false
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
                        .accessibilityLabel("One tap. Total peace of mind.")
                }

                Spacer()

                // Sign in with Apple (adapts to color scheme)
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

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    Text("or").foregroundStyle(.secondary).font(.footnote)
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }

                // Email form
                VStack(spacing: 12) {
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
                }

                // Toggle sign-in / sign-up
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

                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: authViewModel.errorMessage)
        }
    }
}
