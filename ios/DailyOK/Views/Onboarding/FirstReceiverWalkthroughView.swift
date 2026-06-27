import SwiftUI

/// Multi-step walkthrough that runs an owner from "no receivers yet" to a sent
/// invite. Auto-launches on the Dashboard the first time it loads empty, and
/// can be re-opened from the Dashboard empty state's CTA.
///
/// Steps: Welcome → How it works → Receiver details (form) → Invite sent
struct FirstReceiverWalkthroughView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentStep: WalkthroughStep = .welcome
    @State private var name = ""
    @State private var phone = ""
    @State private var checkinTime = Self.defaultCheckinTime
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: FormField?

    let onInviteSent: () async -> Void

    enum WalkthroughStep: Int, CaseIterable {
        case welcome
        case howItWorks
        case receiverDetails
        case inviteSent
    }

    private enum FormField { case name, phone }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ZStack {
                    stepContent
                        .id(currentStep)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(DailyOKMotion.smoothSpring, value: currentStep)

                footer
            }
            .background(AmbientBackground(tone: .calm))
            .navigationTitle(currentStep == .inviteSent ? "All Set" : "Add Your First Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if currentStep != .inviteSent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(WalkthroughStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue
                          ? DailyOKColor.brand
                          : Color(.systemGray4))
                    .frame(width: step == currentStep ? 28 : 10, height: 8)
                    .animation(reduceMotion ? nil : DailyOKMotion.smoothSpring, value: currentStep)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(currentStep.rawValue + 1) of \(WalkthroughStep.allCases.count)")
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome: welcomeStep
        case .howItWorks: howItWorksStep
        case .receiverDetails: receiverDetailsStep
        case .inviteSent: inviteSentStep
        }
    }

    private var welcomeStep: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(DailyOKColor.green100)
                        .frame(width: 160, height: 160)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(DailyOKColor.green700)
                }
                .padding(.top, 24)
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Let's add your first family member")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("Daily OK helps you stay connected with the people who matter — a one-tap check-in, peace of mind every day.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var howItWorksStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Here's how it works")
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                FlowStepRow(
                    number: 1,
                    icon: "bell.badge.fill",
                    title: "We send them a daily reminder",
                    detail: "At the time you choose, your family member gets a notification asking how they're doing."
                )

                FlowStepRow(
                    number: 2,
                    icon: "checkmark.circle.fill",
                    title: "They tap \"I'm OK\"",
                    detail: "One tap. No typing. They can also share a quick mood or note if they want."
                )

                FlowStepRow(
                    number: 3,
                    icon: "heart.text.square.fill",
                    title: "You see they checked in",
                    detail: "Their status updates here on your dashboard. If they miss a check-in, you'll get an alert."
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var receiverDetailsStep: some View {
        Form {
            Section {
                TextField("Their name", text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .phone }

                TextField("Phone number", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .phone)
            } header: {
                Text("Who are you adding?")
            } footer: {
                Text("Use the phone number they'll sign into the app with — that's how we automatically connect them to your family.")
            }

            Section {
                DatePicker("Daily check-in time",
                           selection: $checkinTime,
                           displayedComponents: .hourAndMinute)
            } header: {
                Text("When should we ask them?")
            } footer: {
                Text("You can fine-tune the schedule anytime later — weekday/weekend, per-day, pause, escalation alerts, and more.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            if name.isEmpty { focusedField = .name }
        }
    }

    private var inviteSentStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    Text("Invite sent to \(name)!")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("They'll get a text at \(phone) with a link to download Daily OK.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

                Divider()

                Text("What \(displayName) does next:")
                    .font(.headline)

                ReceiverFlowRow(number: 1, icon: "message.fill", text: "Opens the text message you triggered.")
                ReceiverFlowRow(number: 2, icon: "arrow.down.app.fill", text: "Taps the link to download Daily OK.")
                ReceiverFlowRow(number: 3, icon: "phone.fill", text: "Signs in with the same phone number — no codes to type.")
                ReceiverFlowRow(number: 4, icon: "bell.badge.fill", text: "Allows notifications so they get the daily reminder.")
                ReceiverFlowRow(number: 5, icon: "hand.thumbsup.fill", text: "Done. Each day they'll just tap \"I'm OK.\"")

                VStack(alignment: .leading, spacing: 6) {
                    Label("Tip", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("If they don't see the text, double-check the phone number and re-send the invite from the Family tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(12)

                NavigationLink {
                    WatchSetupGuideView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "applewatch")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set up on Apple Watch")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Make checking in even easier — one tap from their wrist.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(12)
                }
                .accessibilityHint("Opens step-by-step instructions for installing Daily OK on an Apple Watch.")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if showsBackButton {
                Button {
                    DailyOKHaptics.selection()
                    advance(by: -1)
                } label: {
                    Text("Back")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.bordered)
                .tint(DailyOKColor.brand)
            }

            Button {
                Task { await primaryAction() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(primaryButtonLabel)
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(primaryButtonDisabled
                                           ? Color(.systemGray3)
                                           : DailyOKColor.brand))
            }
            .disabled(primaryButtonDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    private var showsBackButton: Bool {
        switch currentStep {
        case .welcome, .inviteSent: return false
        case .howItWorks, .receiverDetails: return true
        }
    }

    private var primaryButtonLabel: String {
        switch currentStep {
        case .welcome, .howItWorks: return "Next"
        case .receiverDetails: return isLoading ? "Sending…" : "Send Invite"
        case .inviteSent: return "Done"
        }
    }

    private var primaryButtonDisabled: Bool {
        switch currentStep {
        case .receiverDetails:
            return isLoading
                || name.trimmingCharacters(in: .whitespaces).isEmpty
                || phone.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return false
        }
    }

    // MARK: - Actions

    private func primaryAction() async {
        switch currentStep {
        case .welcome, .howItWorks:
            DailyOKHaptics.selection()
            advance(by: 1)
        case .receiverDetails:
            await sendInvite()
        case .inviteSent:
            DailyOKHaptics.selection()
            dismiss()
        }
    }

    private func advance(by delta: Int) {
        guard let next = WalkthroughStep(rawValue: currentStep.rawValue + delta) else { return }
        focusedField = nil
        withAnimation(reduceMotion ? nil : DailyOKMotion.smoothSpring) {
            currentStep = next
        }
    }

    private func sendInvite() async {
        focusedField = nil
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            guard let family = try await FamilyService.shared.getFamily() else {
                errorMessage = String(localized: "Couldn't find your family. Try restarting the app.")
                return
            }

            // Wire format for the backend — POSIX-locked to keep the 24h "HH:mm"
            // contract stable across user locales (US-IOS044).
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"

            try await FamilyService.shared.inviteReceiver(
                familyId: family.id,
                name: name.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces),
                checkinTime: formatter.string(from: checkinTime)
            )

            await onInviteSent()
            DailyOKHaptics.success()
            withAnimation(DailyOKMotion.smoothSpring) {
                currentStep = .inviteSent
            }
        } catch {
            DailyOKHaptics.error()
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "they" : trimmed
    }

    private static var defaultCheckinTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }
}

// MARK: - Step row helpers

private struct FlowStepRow: View {
    let number: Int
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green100)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(DailyOKColor.green700)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(number).")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DailyOKColor.brand)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReceiverFlowRow: View {
    let number: Int
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(.green)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.top, 2)
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
