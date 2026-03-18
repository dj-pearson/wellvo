import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack {
                // Progress indicator
                ProgressView(value: Double(viewModel.currentStep.rawValue), total: Double(OnboardingStep.allCases.count - 1))
                    .tint(.green)
                    .padding(.horizontal)

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
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

                Spacer()
            }
            .animation(.easeInOut, value: viewModel.currentStep)
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Welcome to Wellvo")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("One tap. Total peace of mind.\nLet's set up your family check-ins.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Get Started") { viewModel.advance() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
        }
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
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
            .tint(.green)
            .controlSize(.large)
            .disabled(viewModel.familyName.isEmpty || viewModel.isLoading)
        }
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
        .padding()
    }

    private var notificationsStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Enable Notifications")
                .font(.title)
                .fontWeight(.bold)

            Text("Notifications are essential for Wellvo.\nYou'll be alerted when your family members check in — or if they miss one.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Enable Notifications") {
                Task { await viewModel.requestNotificationPermission() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
        .padding()
    }

    private var choosePlanStep: some View {
        VStack(spacing: 24) {
            Text("Choose Your Plan")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                planCard(
                    title: "Free",
                    price: "Free",
                    features: ["1 Receiver", "Daily check-ins", "Basic escalation"],
                    isHighlighted: false
                ) {
                    viewModel.advance()
                }

                planCard(
                    title: "Family",
                    price: "$4.99/mo",
                    features: ["2 Receivers", "2 Viewers", "Full escalation", "Mood tracking"],
                    isHighlighted: true
                ) {
                    viewModel.advance()
                }

                planCard(
                    title: "Family+",
                    price: "$9.99/mo",
                    features: ["5 Receivers", "5 Viewers", "Priority support", "All features"],
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
            .background(isHighlighted ? Color.green : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isHighlighted ? .white : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHighlighted ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var completeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

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
            .tint(.green)
            .controlSize(.large)
        }
        .padding()
    }
}
