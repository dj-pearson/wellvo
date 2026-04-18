import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var largeIconSize: CGFloat = 80
    @ScaledMetric(relativeTo: .title) private var mediumIconSize: CGFloat = 60

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(tone: ambientTone(for: viewModel.currentStep))

                VStack {
                    // Progress indicator on a glass pill
                    ProgressView(value: Double(viewModel.currentStep.rawValue), total: Double(OnboardingStep.allCases.count - 1))
                        .tint(DailyOKColor.green500)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .glassPill(style: .ultraThin)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .accessibilityLabel("Onboarding progress: step \(viewModel.currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")

                    Spacer()

                    Group {
                        switch viewModel.currentStep {
                        case .welcome:
                            welcomeStep
                        case .userType:
                            userTypeStep
                        case .createFamily:
                            createFamilyStep
                        case .choosePlan:
                            choosePlanStep
                        case .addReceiver:
                            addReceiverStep
                        case .notifications:
                            notificationsStep
                        case .complete:
                            completeStep
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                    .transaction { t in if reduceMotion { t.animation = nil } }

                    Spacer()
                }
                .animation(reduceMotion ? nil : DailyOKMotion.smoothSpring, value: viewModel.currentStep)
            }
        }
    }

    private func ambientTone(for step: OnboardingStep) -> AmbientBackground.Tone {
        switch step {
        case .welcome, .complete: return .calm
        case .choosePlan: return .warm
        default: return .neutral
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green300.opacity(0.45))
                    .frame(width: largeIconSize * 1.8, height: largeIconSize * 1.8)
                    .blur(radius: 28)
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: largeIconSize))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green400, DailyOKColor.green600],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .accessibilityHidden(true)
            }

            Text("Welcome to Daily OK")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("One tap. Total peace of mind.\nLet's set up your family check-ins.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Get Started") { viewModel.advance() }
                .buttonStyle(.borderedProminent)
                .tint(DailyOKColor.green500)
                .controlSize(.large)
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .padding()
    }

    private var userTypeStep: some View {
        VStack(spacing: 24) {
            Text("Who do you want to\ncheck on?")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                userTypeButton(
                    title: "Aging Parent",
                    subtitle: "Keep tabs on Mom or Dad",
                    icon: "figure.and.child.holdinghands",
                    type: .agingParent
                )

                userTypeButton(
                    title: "Teenager",
                    subtitle: "A simple daily check-in",
                    icon: "person.fill",
                    type: .teenager
                )

                userTypeButton(
                    title: "Someone Else",
                    subtitle: "Friend, roommate, or other",
                    icon: "person.2.fill",
                    type: .other
                )
            }
        }
        .padding()
    }

    private func userTypeButton(title: String, subtitle: String, icon: String, type: UserTypeSelection) -> some View {
        Button {
            viewModel.userTypeSelection = type
            viewModel.advance()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .glassCard(style: .thin, radius: DailyOKGlass.radiusMedium, elevation: DailyOKElevation.level2)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(title): \(subtitle)")
        .accessibilityHint("Double tap to select \(title)")
    }

    private var createFamilyStep: some View {
        VStack(spacing: 24) {
            Text("Name Your Family Group")
                .font(.title)
                .fontWeight(.bold)

            TextField("e.g. The Smith Family", text: $viewModel.familyName)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .padding(.horizontal)

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            Button {
                Task { await viewModel.createFamily() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text("Create Family")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green500)
            .controlSize(.large)
            .disabled(viewModel.familyName.isEmpty || viewModel.isLoading)
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .padding()
    }

    private var addReceiverStep: some View {
        VStack(spacing: 24) {
            Text("Add Your First Receiver")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                TextField("Their Name", text: $viewModel.receiverName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)

                TextField("Their Phone Number", text: $viewModel.receiverPhone)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)

                DatePicker("Daily Check-In Time", selection: $viewModel.checkinTime, displayedComponents: .hourAndMinute)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal)

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            Button {
                Task { await viewModel.inviteReceiver() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text("Send Invite")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(viewModel.receiverName.isEmpty || viewModel.receiverPhone.isEmpty || viewModel.isLoading)

            Button("Skip for now") { viewModel.advance() }
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .padding()
    }

    private var notificationsStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.goldLight.opacity(0.5))
                    .frame(width: mediumIconSize * 2, height: mediumIconSize * 2)
                    .blur(radius: 24)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: mediumIconSize))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green500, DailyOKColor.teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
            }

            Text("Enable Notifications")
                .font(.title)
                .fontWeight(.bold)

            Text("Notifications are essential for Daily OK.\nYou'll be alerted when your family members check in — or if they miss one.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Enable Notifications") {
                Task { await viewModel.requestNotificationPermission() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green500)
            .controlSize(.large)
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .padding()
    }

    private var choosePlanStep: some View {
        VStack(spacing: 24) {
            Text("Choose Your Plan")
                .font(.title)
                .fontWeight(.bold)

            Text("Start with a 7-day free trial. Cancel anytime.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                planCard(
                    title: "Caregiver",
                    price: "$3.99/mo",
                    features: ["1 Receiver", "3 Viewers", "Full escalation", "Pattern alerts"],
                    isHighlighted: true
                ) {
                    viewModel.advance()
                }

                planCard(
                    title: "Family",
                    price: "$6.99/mo",
                    features: ["3 Receivers", "5 Viewers", "Clinician PDF export", "Kid mode"],
                    isHighlighted: false
                ) {
                    viewModel.advance()
                }

                planCard(
                    title: "Family+",
                    price: "$9.99/mo",
                    features: ["6 Receivers", "10 Viewers", "Critical Alerts", "Priority support"],
                    isHighlighted: false
                ) {
                    viewModel.advance()
                }
            }

            Text("You can change your plan anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func planCard(title: String, price: String, features: [String], isHighlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(price)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isHighlighted ? .white : .green)
                }

                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .green)
                        Text(feature)
                            .font(.caption)
                            .foregroundStyle(isHighlighted ? .white.opacity(0.9) : .secondary)
                    }
                }
            }
            .padding()
            .background(
                Group {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous)
                            .fill(
                                LinearGradient(colors: [DailyOKColor.green500, DailyOKColor.green600],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous)
                                    .strokeBorder(DailyOKGlass.strokeLight, lineWidth: 0.75)
                            )
                    }
                }
            )
            .foregroundStyle(isHighlighted ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous))
            .shadow(color: .black.opacity(isHighlighted ? 0.18 : 0.08),
                    radius: isHighlighted ? DailyOKElevation.level3 : DailyOKElevation.level2,
                    y: isHighlighted ? 6 : 3)
        }
        .buttonStyle(.pressable)
    }

    private var completeStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green300.opacity(0.5))
                    .frame(width: largeIconSize * 1.8, height: largeIconSize * 1.8)
                    .blur(radius: 30)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: largeIconSize))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green400, DailyOKColor.green600],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.bounce, value: viewModel.currentStep)
                    .accessibilityHidden(true)
            }

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your family's check-in system is ready.\nYou'll see your dashboard next.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Go to Dashboard") {
                appState.isOnboarding = false
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green500)
            .controlSize(.large)
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .padding()
    }
}
