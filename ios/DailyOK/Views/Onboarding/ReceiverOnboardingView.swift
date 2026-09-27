import SwiftUI
import UserNotifications

/// Simplified onboarding flow for Receivers (and co-caregivers).
/// Supports two paths:
/// 1. Token-based (deep link) — the invite link's token
/// 2. Auto-join (phone match) — the verified phone number matched an invite
///
/// Nothing is joined until the person says so. The link used to be redeemed
/// as this screen appeared, and a phone match during launch, so someone whose
/// number was on a stranger's invite (or who tapped a link someone sent them)
/// became a member watched every day without being told by whom. Step 0 now
/// asks "Join Sarah's family?" and says who will see their check-ins; only
/// "Join" redeems, and "This isn't me" leaves nothing behind.
struct ReceiverOnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentStep = 0
    @State private var isProcessing = false
    // nil until the server provides the real time — never fabricate "8:00 AM"
    // (US-IOS112).
    @State private var checkinTimeDisplay: String?
    @State private var ownerName: String?
    @State private var errorMessage: String?
    /// True when a token-based invite failed to redeem. Blocks the false "All set"
    /// success screen and surfaces Try Again / Cancel instead of stranding the
    /// user as a receiver of no family.
    @State private var joinFailed = false
    /// True once the receiver was asked for notification permission and denied it.
    @State private var notificationDenied = false
    /// What the invite made them. A co-caregiver invite makes a viewer, who is
    /// alerted about missed check-ins and never asked to check in.
    @State private var joinedRole: UserRole = .receiver
    /// What joining would mean, before anything is redeemed.
    @State private var preview: JoinPreview?
    /// The join has happened (here, or already by an older server).
    @State private var hasJoined = false

    private var isCaregiver: Bool { joinedRole == .viewer }

    /// Nil when using auto-join (phone match) flow.
    let inviteToken: String?

    var body: some View {
        ZStack {
            AmbientBackground(tone: currentStep == 2 ? .calm : .neutral)

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { step in
                        Capsule()
                            .fill(step <= currentStep ? DailyOKColor.green500 : Color.secondary.opacity(0.3))
                            .frame(width: step == currentStep ? 24 : 8, height: 8)
                            .animation(reduceMotion ? nil : DailyOKMotion.smoothSpring, value: currentStep)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassPill(style: .ultraThin)
                .padding(.top, 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(currentStep + 1) of 3")

                ScrollView {
                    VStack {
                        Group {
                            switch currentStep {
                            case 0:
                                welcomeStep
                            case 1:
                                notificationStep
                            default:
                                doneStep
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                        .transaction { t in if reduceMotion { t.animation = nil } }
                        .animation(reduceMotion ? nil : DailyOKMotion.smoothSpring, value: currentStep)
                    }
                    .padding(.vertical, 24)
                }
            }
            .padding(.horizontal, 32)
            .task { await processJoin() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings after turning notifications on: notice,
            // instead of still saying they're off.
            guard phase == .active, currentStep == 1, notificationDenied else { return }
            Task {
                if await PushNotificationService.shared.checkPermissionStatus() == .authorized {
                    notificationDenied = false
                    advanceToDone()
                }
            }
        }
    }

    // MARK: - Step 1: Welcome / consent

    @ViewBuilder
    private var welcomeStep: some View {
        if let preview, !hasJoined {
            JoinConsentCard(
                preview: preview,
                isProcessing: isProcessing,
                errorMessage: errorMessage,
                onJoin: { Task { await confirmJoin() } },
                onDecline: { decline() }
            )
        } else {
            joinedWelcome
        }
    }

    private var joinedWelcome: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green300.opacity(0.45))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(DailyOKColor.green600)
                    .accessibilityHidden(true)
            }

            Text("Welcome to Daily OK")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            if isProcessing && !hasJoined {
                // A slow connection used to look like a dead Continue button.
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting you to your family…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if isCaregiver {
                Text(ownerName.map { "\($0) added you as a co-caregiver." } ?? "You've been added as a co-caregiver.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                Text("We'll tell you if someone asks for help or misses a check-in. You won't be asked to check in yourself.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            } else if hasJoined {
                if let ownerName {
                    Text("You're in \(ownerName)'s family. \(ownerName) will see when you check in.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }

                Text(checkinTimeDisplay.map { "Every day at **\($0)**, we'll send you a notification." }
                     ?? "We'll remind you each day with a notification.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                Text("Just tap **\"I'm OK\"** and that's it.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(DailyOKColor.error)
                    .multilineTextAlignment(.center)
            }

            if joinFailed {
                // Invite couldn't be redeemed — don't advance to a fake success.
                VStack(spacing: 12) {
                    Button("Try Again") {
                        Task { await retryJoin() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DailyOKColor.green700)
                    .controlSize(.large)
                    .disabled(isProcessing)

                    Text("If this keeps happening, ask your family to send you a new invite.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Cancel") { cancelJoin() }
                        .foregroundStyle(.secondary)
                        .disabled(isProcessing)
                }
            } else if hasJoined {
                Button("Continue") { goToNotificationsOrDone() }
                    .buttonStyle(.borderedProminent)
                    .tint(DailyOKColor.green700)
                    .controlSize(.large)
                    .disabled(isProcessing)
            }
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
    }

    // MARK: - Step 2: Notifications

    private var notificationStep: some View {
        NotificationPermissionStepCard(
            isCaregiver: isCaregiver,
            denied: $notificationDenied,
            onFinished: { advanceToDone() }
        )
    }

    private func advanceToDone() {
        if reduceMotion {
            currentStep = 2
        } else {
            withAnimation(DailyOKMotion.smoothSpring) { currentStep = 2 }
        }
    }

    /// Skip the permission step when notifications are already on.
    private func goToNotificationsOrDone() {
        Task {
            let status = await PushNotificationService.shared.checkPermissionStatus()
            if status == .authorized {
                advanceToDone()
            } else if reduceMotion {
                currentStep = 1
            } else {
                withAnimation(DailyOKMotion.smoothSpring) { currentStep = 1 }
            }
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green300.opacity(0.55))
                    .frame(width: 150, height: 150)
                    .blur(radius: 32)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(DailyOKColor.green600)
                    .accessibilityHidden(true)
            }

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text(isCaregiver
                 ? "You'll be alerted if someone asks for help or misses a check-in, and you can see how everyone's doing."
                 : "\(ownerName ?? String(localized: "Your family")) will be notified when you check in each day.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Button(isCaregiver ? "Open Daily OK" : "Start Checking In") {
                appState.pendingInviteToken = nil
                appState.pendingAutoJoin = nil
                appState.isOnboarding = false
                appState.currentUserRole = joinedRole
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green700)
            .controlSize(.large)
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
    }

    // MARK: - Join Logic

    private func processJoin() async {
        guard preview == nil, !hasJoined else { return }
        if let token = inviteToken {
            await previewInviteByToken(token)
        } else if let autoJoin = appState.pendingAutoJoin {
            if autoJoin.isPreview && !autoJoin.alreadyMember {
                applyPreview(autoJoin.joinPreview)
            } else {
                // An older server already joined (or they were already in).
                applyJoined(
                    role: autoJoin.role == UserRole.viewer.rawValue ? .viewer : .receiver,
                    checkinTime: autoJoin.checkinTime,
                    owner: autoJoin.ownerName
                )
            }
        }
    }

    private func previewInviteByToken(_ token: String) async {
        isProcessing = true
        errorMessage = nil
        do {
            let step = try await FamilyService.shared.previewInvite(token: token)
            switch step {
            case .preview(let described):
                if described.alreadyMember {
                    applyJoined(role: described.role, checkinTime: described.checkinTime, owner: described.ownerName)
                } else {
                    applyPreview(described)
                }
            case .joined(let details):
                applyJoined(role: details.role ?? .receiver, checkinTime: details.checkinTime, owner: details.ownerName)
            }
            joinFailed = false
        } catch let error as EdgeFunctionsClient.HTTPError where error.status == 409 {
            applyJoined(role: .receiver, checkinTime: nil, owner: nil)
            await adoptServerRoleIfMember()
        } catch {
            await failOrRecover(error)
        }
        isProcessing = false
    }

    /// "Join" on the consent card: now redeem.
    private func confirmJoin() async {
        isProcessing = true
        errorMessage = nil
        if let token = inviteToken {
            do {
                let joined = try await FamilyService.shared.acceptInvite(token: token)
                applyJoined(role: joined.role ?? preview?.role ?? .receiver,
                            checkinTime: joined.checkinTime ?? preview?.checkinTime,
                            owner: joined.ownerName ?? preview?.ownerName)
                joinFailed = false
            } catch let error as EdgeFunctionsClient.HTTPError where error.status == 409 {
                applyJoined(role: preview?.role ?? .receiver, checkinTime: preview?.checkinTime, owner: preview?.ownerName)
                await adoptServerRoleIfMember()
            } catch {
                await failOrRecover(error)
            }
        } else {
            do {
                let check = try await FamilyService.shared.checkAutoJoin(preview: false, familyId: preview?.familyId)
                switch check {
                case .matched(let result):
                    applyJoined(
                        role: result.role == UserRole.viewer.rawValue ? .viewer : .receiver,
                        checkinTime: result.checkinTime ?? preview?.checkinTime,
                        owner: result.ownerName ?? preview?.ownerName
                    )
                case .blocked(let message):
                    errorMessage = message
                case .noMatch:
                    await failOrRecover(nil)
                }
            } catch {
                await failOrRecover(error)
            }
        }
        isProcessing = false
        if hasJoined { goToNotificationsOrDone() }
    }

    /// A failure may hide a success: if the first request joined and only its
    /// answer was lost, a retry is refused as "invalid or expired". Ask the
    /// server where this person belongs before calling it a failure.
    private func failOrRecover(_ error: Error?) async {
        if let role = try? await FamilyService.shared.getCurrentUserRole(), role != .owner {
            applyJoined(role: role, checkinTime: preview?.checkinTime, owner: preview?.ownerName)
            joinFailed = false
            return
        }
        errorMessage = error.map {
            edgeErrorMessage($0, fallback: String(localized: "Could not join family. The invite may have expired."))
        } ?? String(localized: "This invite is no longer available. Ask your family to send a new one.")
        // On the consent card the error shows inline; elsewhere offer Try Again.
        if preview == nil { joinFailed = true }
    }

    /// After a 409 "already a member", use the role the server has.
    private func adoptServerRoleIfMember() async {
        if let role = try? await FamilyService.shared.getCurrentUserRole(), role != .owner {
            joinedRole = role
        }
    }

    private func applyPreview(_ described: JoinPreview) {
        preview = described
        joinedRole = described.role
        ownerName = described.displayOwnerName
        if let time = described.checkinTime {
            checkinTimeDisplay = formatCheckinTimeForDisplay(time)
        }
    }

    private func applyJoined(role: UserRole, checkinTime: String?, owner: String?) {
        joinedRole = role == .viewer ? .viewer : .receiver
        if let time = checkinTime {
            checkinTimeDisplay = formatCheckinTimeForDisplay(time)
        }
        if let owner = JoinPreview.presentableName(owner) {
            ownerName = owner
        }
        errorMessage = nil
        hasJoined = true
    }

    private func retryJoin() async {
        if preview != nil {
            await confirmJoin()
        } else if let token = inviteToken {
            await previewInviteByToken(token)
        }
    }

    /// "This isn't me": nothing was joined. Forget the invite on this device
    /// and go to the start screen.
    private func decline() {
        if inviteToken == nil, let familyId = preview?.familyId ?? appState.pendingAutoJoin?.familyId,
           let userId = AuthService.shared.storedUserId {
            appState.declineAutoJoin(familyId: familyId, for: userId)
        }
        appState.pendingInviteToken = nil
        appState.pendingAutoJoin = nil
        appState.currentUserRole = nil
        appState.isOnboarding = false
    }

    /// Abandon a failed invite: clear the pending deep link and ask the server
    /// again where this person belongs (a join whose answer was lost may have
    /// worked), instead of stranding a member on the get-started screen.
    private func cancelJoin() {
        appState.pendingInviteToken = nil
        appState.pendingAutoJoin = nil
        appState.currentUserRole = nil
        appState.isOnboarding = false
        appState.roleResolution = .resolving
        appState.roleRefreshRequest += 1
    }
}

// MARK: - Shared join UI

/// "Join Sarah's family?" — shown before any invite, phone match or setup
/// code is redeemed. Says whose family, as what, and who will see this
/// person's check-ins, battery and location, with a way to say no.
struct JoinConsentCard: View {
    let preview: JoinPreview
    let isProcessing: Bool
    let errorMessage: String?
    let onJoin: () -> Void
    let onDecline: () -> Void
    var declineTitle: LocalizedStringKey = "This isn't me"

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: preview.role == .viewer ? "person.2.circle.fill" : "house.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(DailyOKColor.green600)
                .accessibilityHidden(true)

            Text(preview.headline)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityAddTraits(.isHeader)

            if let family = JoinPreview.presentableName(preview.familyName) {
                Label(family, systemImage: "person.3.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if let name = JoinPreview.presentableName(preview.inviteName) {
                Text("The invite is for **\(name)**.")
                    .font(.body)
                    .multilineTextAlignment(.center)
            }

            Text(preview.sharingSentence)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if preview.role != .viewer, let time = preview.checkinTime {
                Text("You'll get a reminder each day at **\(formatCheckinTimeForDisplay(time))**.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(DailyOKColor.error)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button(action: onJoin) {
                    Group {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Text("Join")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(DailyOKColor.green700)
                .controlSize(.large)
                .disabled(isProcessing)

                Button(action: onDecline) {
                    Text(declineTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(.secondary)
                .disabled(isProcessing)
                .accessibilityHint("Doesn't join. Nothing is shared.")
            }
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
    }
}

/// The notification permission ask every joiner goes through (link, phone
/// match or setup code). Without it no push token is ever registered, so the
/// daily reminder never arrives and every day reads as a missed check-in.
struct NotificationPermissionStepCard: View {
    let isCaregiver: Bool
    @Binding var denied: Bool
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.teal.opacity(0.4))
                    .frame(width: 120, height: 120)
                    .blur(radius: 26)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DailyOKColor.green600)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
            }

            Text("One Last Thing")
                .font(.title)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text(isCaregiver
                 ? "Allow notifications so we can tell you right away if someone asks for help or misses a check-in."
                 : "We need to send you a notification each day so you can check in.\n\nWithout this, your family won't know you're OK.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            if denied {
                // The system won't re-prompt once denied — guide to Settings rather
                // than silently advancing to "All set" with no daily reminder.
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DailyOKColor.gold)
                            .accessibilityHidden(true)
                        // Primary-colored text: gold on light glass was ~2:1.
                        Text(isCaregiver
                             ? "Notifications are turned off. You won't hear about a missed check-in until you turn them on in Settings."
                             : "Notifications are turned off. You won't get your daily check-in reminder until you turn them on in Settings.")
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .accessibilityElement(children: .combine)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DailyOKColor.green700)
                    .controlSize(.large)

                    Button("Continue anyway") { onFinished() }
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Allow Notifications") {
                    Task {
                        let granted = (try? await PushNotificationService.shared.requestPermission()) ?? false
                        if granted {
                            onFinished()
                        } else {
                            denied = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DailyOKColor.green700)
                .controlSize(.large)
            }
        }
        .padding(24)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
    }
}
