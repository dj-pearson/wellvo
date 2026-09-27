import SwiftUI
import CoreLocation

struct ReceiverHomeView: View {
    @StateObject private var viewModel = ReceiverViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("receiver.simpleModeOffered") private var simpleModeOffered = false
    @State private var showSimpleModeOffer = false
    @State private var buttonScale: CGFloat = 1.0
    @State private var isPulsing = false
    @State private var showCheckmark = false
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var checkmarkOpacity: Double = 0.0
    @State private var showSignOutConfirmation = false
    @State private var showCelebration = false
    @State private var showHealthSharing = false
    @State private var showLocationSharing = false
    /// Export and account deletion (App Store 5.1.1(v)): receivers had neither.
    @State private var showAccountSheet = false
    /// An urgent send waiting for "Send Help Alert" in the confirmation.
    @State private var pendingHelp: ReceiverHelpKind?
    /// Width available to the content, so the button never outgrows the screen
    /// at the largest text sizes.
    @State private var contentWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .largeTitle) private var buttonDiameter: CGFloat = 200
    @ScaledMetric(relativeTo: .title) private var tapIconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var tapTextSize: CGFloat = 28

    /// Text on a light surface for help actions: red-700, ~6:1 on white.
    /// DailyOKColor.error (#EF4444) is too light for text.
    private static let helpRed = Color(red: 0.725, green: 0.110, blue: 0.110)
    /// Teal-700 (#0F766E): the kid button's second stop, white text readable.
    private static let teal700 = Color(red: 0.059, green: 0.463, blue: 0.431)

    private var isKidMode: Bool {
        viewModel.receiverMode == .kid
    }

    /// Senior Simple Mode: extra-large, calm, high-contrast, low-clutter.
    private var isSimpleMode: Bool {
        viewModel.simpleMode
    }

    /// The main circle. Simple Mode is larger; both are clamped to the space
    /// available — at AX5 the Simple Mode circle was ~415 pt, wider than a
    /// phone, and cut off at both edges.
    private var effectiveDiameter: CGFloat {
        let raw = isSimpleMode ? buttonDiameter * 1.18 : buttonDiameter
        guard contentWidth > 0 else { return raw }
        return min(raw, max(160, contentWidth - 48))
    }

    /// "Sarah" or "your family".
    private var ownerLabel: String {
        viewModel.ownerName ?? String(localized: "your family")
    }

    /// Greeting that matches the time of day rather than always "Good morning!".
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return String(localized: "Good morning!")
        case 12..<17: return String(localized: "Good afternoon!")
        case 17..<22: return String(localized: "Good evening!")
        default: return String(localized: "Hello!")
        }
    }

    var body: some View {
        ZStack {
            AmbientBackground(tone: viewModel.hasCheckedInToday ? .calm : .warm)

            ScrollView {
                VStack(spacing: 24) {
                    NotificationPermissionBanner()
                        .padding(.horizontal)

                    if viewModel.isOffline {
                        offlineBanner
                    }

                    Spacer().frame(height: 20)

                    // Streak + 7-day consistency header chips. Both chips
                    // self-hide when there isn't enough history (streak < 2,
                    // consistency < 50%), so first-day receivers see no header.
                    if !isSimpleMode && (viewModel.streakDays >= 2 || Streaks.badge(consistencyPercent: viewModel.consistencyPercent) != .none) {
                        HStack(spacing: 8) {
                            StreakChip(streakDays: viewModel.streakDays, showsDayLabel: true)
                            ConsistencyChip(badge: Streaks.badge(consistencyPercent: viewModel.consistencyPercent))
                        }
                    }

                    if let help = viewModel.helpStatus {
                        helpStatusCard(help).padding(.horizontal)
                    }

                    if viewModel.hasCheckedInToday {
                        if viewModel.helpStatus == nil {
                            statusCard.padding(.horizontal)
                        } else if let actionMessage = viewModel.actionMessage {
                            // The status card (which shows it) is hidden
                            // under a help request; a failed setting still
                            // has to say so.
                            warningText(actionMessage)
                        }
                        if let notice = viewModel.noticeMessage {
                            noticeText(notice)
                        }
                    } else {
                        if viewModel.owesLaterAnswer, let earlier = viewModel.lastCheckIn {
                            earlierCheckInLine(earlier)
                        }
                        if viewModel.hasPendingRequest {
                            pendingRequestBanner.padding(.horizontal)
                        }
                        checkInButton
                        if viewModel.hasPendingRequest && viewModel.canSnooze {
                            snoozeButton.padding(.horizontal)
                        }
                        if let until = viewModel.snoozedUntil {
                            noticeText(String(localized: "We'll remind you at \(until.formatted(date: .omitted, time: .shortened)). Your family won't be alerted before then."))
                        }
                        if let actionMessage = viewModel.actionMessage {
                            // A failed snooze or setting: say so, but no "Try
                            // Again" — that button checks in.
                            warningText(actionMessage)
                        }
                        if let notice = viewModel.noticeMessage {
                            noticeText(notice)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        checkInErrorBlock(errorMessage)
                    }

                    helpSection
                        .padding(.horizontal)

                    Spacer().frame(height: 20)
                }
                .padding()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
                // VoiceOver hears outcomes that appear away from focus.
                .announce(viewModel.snoozedUntil) { until in
                    until.map { String(localized: "Snoozed. We'll remind you at \($0.formatted(date: .omitted, time: .shortened)).") }
                }
                .announce(viewModel.errorMessage) { $0 }
                .announce(viewModel.actionMessage) { $0 }
                .announce(viewModel.noticeMessage) { $0 }
                .announce(viewModel.helpFailure) { $0?.message }
                .announce(viewModel.helpStatus) { status in
                    guard let status else { return nil }
                    if let who = status.acknowledgedBy { return String(localized: "\(who) is on it.") }
                    return status.kind.sentMessage(owner: viewModel.ownerName)
                }
            }

            // Discreet menu — sign out + link into iOS notification settings.
            // Placed top-right as an overlay so it stays accessible from either
            // the check-in button state or the "all set" state without
            // cluttering the main content.
            VStack {
                HStack {
                    Spacer()
                    Menu {
                        // Receiver can self-serve their own display preferences
                        // here, instead of relying on a remote owner to toggle
                        // Simple Mode for them. Saved through a receiver-only
                        // RPC (00061); a failure rolls the toggle back.
                        Section("Display") {
                            Toggle(isOn: Binding(
                                get: { viewModel.simpleMode },
                                set: { newValue in Task { await viewModel.updateSimpleMode(newValue) } }
                            )) {
                                Label("Simple Mode", systemImage: "textformat.size.larger")
                            }
                            Toggle(isOn: Binding(
                                get: { viewModel.audioConfirmationEnabled },
                                set: { newValue in Task { await viewModel.updateAudioConfirmation(newValue) } }
                            )) {
                                Label("Spoken Confirmation", systemImage: "speaker.wave.2.fill")
                            }
                        }
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Notification Settings", systemImage: "bell.badge")
                        }
                        Button {
                            showLocationSharing = true
                        } label: {
                            Label("Location Sharing", systemImage: "location")
                        }
                        Button {
                            showHealthSharing = true
                        } label: {
                            Label("Activity Sharing", systemImage: "figure.walk")
                        }
                        Button {
                            showAccountSheet = true
                        } label: {
                            Label("Account & Privacy", systemImage: "person.crop.circle")
                        }
                        Button(role: .destructive) {
                            showSignOutConfirmation = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundStyle(DailyOKColor.green700)
                            .frame(width: 44, height: 44) // full-size tap target
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More options")
                    .accessibilityAddTraits(.isButton)
                }
                Spacer()
            }
            .padding(.horizontal, 8)

            CelebrationOverlay(
                isVisible: $showCelebration,
                message: String(localized: "Checked in. Your family has been notified.")
            ) {
                showCelebration = false
            }
        }
        .sheet(isPresented: $showHealthSharing) {
            HealthSharingView()
        }
        .sheet(isPresented: $showLocationSharing) {
            LocationSharingSheet()
        }
        .sheet(isPresented: $showAccountSheet) {
            ReceiverAccountSheet(leave: viewModel.familyId.map {
                ReceiverLeaveContext(familyId: $0, familyName: viewModel.familyName, ownerName: viewModel.ownerName)
            })
            .environmentObject(authViewModel)
            .environmentObject(appState)
        }
        .task {
            await viewModel.loadStatus()
            // US-IOS017: refresh the opt-in passive "active today" signal (no-op
            // unless the receiver has turned activity sharing on).
            await HealthService.shared.reportTodayIfEnabled(timezone: viewModel.receiverTimezone)
            // US-IOS036: offer Simple Mode once if the receiver is clearly using
            // accessibility settings (large text or VoiceOver) and hasn't already
            // enabled it. Helps seniors who set up their own device.
            if !simpleModeOffered, !viewModel.simpleMode,
               dynamicTypeSize.isAccessibilitySize || UIAccessibility.isVoiceOverRunning {
                simpleModeOffered = true
                showSimpleModeOffer = true
            }
        }
        .alert("Make check-in easier?", isPresented: $showSimpleModeOffer) {
            Button("Turn On Simple Mode") {
                Task { await viewModel.updateSimpleMode(true) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Simple Mode shows a larger, calmer screen with a bigger “I'm OK” button. You can change this anytime from the menu.")
        }
        .alert(
            pendingHelp?.confirmTitle(owner: viewModel.ownerName) ?? "",
            isPresented: Binding(
                get: { pendingHelp != nil },
                set: { if !$0 { pendingHelp = nil } }
            ),
            presenting: pendingHelp
        ) { kind in
            Button(kind == .callMe ? String(localized: "Ask to Call") : String(localized: "Send Help Alert"), role: .destructive) {
                Task { await viewModel.sendHelp(kind) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { kind in
            Text(kind == .callMe
                 ? String(localized: "\(ownerLabel.capitalizedFirst) will get an urgent alert asking them to call you.")
                 : (viewModel.ownerName.map { String(localized: "\($0) and your family will get an urgent alert right now.") }
                    ?? String(localized: "Your family will get an urgent alert right now.")))
        }
        // If a silent push request arrived while the app was backgrounded, or the
        // user checked in on another device, re-fetch on foreground so the home
        // screen reflects the true state instead of stale "please check in" UI.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await viewModel.loadStatus()
                    // "Active today" only counted if the app was launched fresh;
                    // refresh it on every foreground.
                    await HealthService.shared.reportTodayIfEnabled(timezone: viewModel.receiverTimezone)
                }
            }
        }
        // Simple Mode turned on while the button is showing (the launch-time
        // offer): stop the pulse it is meant to remove.
        .onChange(of: viewModel.simpleMode) { _, isOn in
            if isOn {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isPulsing = false
                    buttonScale = 1.0
                }
            }
        }
        // When queued offline check-ins sync to the server, reload so the
        // "you're all set" card reflects the now-persisted check-in (or
        // vice-versa if the server rejected it).
        .onReceive(NotificationCenter.default.publisher(for: OfflineCheckInService.didSyncCheckIns)) { _ in
            Task { await viewModel.loadStatus(force: true) }
        }
        // Checked in from a notification while this screen was up: show
        // "all set" now instead of an "I'm OK" button for a done check-in.
        .onReceive(NotificationCenter.default.publisher(for: ReceiverCheckInAftermath.didCheckIn)) { _ in
            Task { await viewModel.loadStatus(force: true) }
        }
        // A check-in tapped on the Apple Watch should immediately flip the phone
        // to "all set" rather than keep prompting (US-IOS082).
        .onReceive(NotificationCenter.default.publisher(for: PhoneWatchSync.didReceiveWatchCheckIn)) { _ in
            Task { await viewModel.loadStatus(force: true) }
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                DailyOKHaptics.warning()
                Task { await authViewModel.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Signing out doesn't stop the family's check-ins — it only
            // silences the reminders, so the next missed day escalates.
            Text("You won't get check-in reminders, but \(ownerLabel) will still be alerted when a check-in is missed. To stop check-ins, use Account & Privacy → Leave family.")
        }
    }

    // MARK: - Banners and messages

    private var offlineBanner: some View {
        let count = viewModel.pendingOfflineCount
        let text: String
        if count == 1 {
            text = String(localized: "Offline — 1 check-in will send when you're back online")
        } else if count > 1 {
            text = String(localized: "Offline — \(count) check-ins will send when you're back online")
        } else {
            text = String(localized: "You're offline")
        }
        return HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(DailyOKColor.gold)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.primary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassPill(style: .thin)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
    }

    /// Neutral confirmation text.
    private func noticeText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .transition(.opacity)
    }

    /// Something didn't work (snooze, undo, a setting). Readable text with a
    /// gold icon — gold text on a light surface was ~2:1.
    private func warningText(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(DailyOKColor.gold)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .font(.subheadline)
        .padding(.horizontal)
    }

    private func earlierCheckInLine(_ earlier: CheckIn) -> some View {
        let time = earlier.checkedInAt.formatted(date: .omitted, time: .shortened)
        let text = viewModel.hasPendingRequest
            ? String(localized: "You checked in at \(time). Your family is asking again.")
            : String(localized: "You checked in at \(time). Time for your next check-in.")
        return Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private func checkInErrorBlock(_ message: String) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Self.helpRed)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }

            switch viewModel.errorRecovery {
            case .retry:
                Button {
                    Task { await viewModel.performCheckIn() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 120, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(DailyOKColor.green700)
            case .signIn:
                // Retrying with a dead session can never work; "Try Again"
                // used to loop here forever.
                Button {
                    Task { await authViewModel.signOut() }
                } label: {
                    Text("Sign In Again")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 120, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(DailyOKColor.green700)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal)
    }

    private var pendingRequestBanner: some View {
        let title: String
        if viewModel.pendingRequestType == .onDemand {
            title = String(localized: "\(ownerLabel.capitalizedFirst) is checking on you")
        } else {
            title = isKidMode
                ? String(localized: "Your family wants to hear from you!")
                : String(localized: "Time for your check-in")
        }
        let asked = viewModel.pendingRequestAskedAt.map {
            String(localized: "Asked at \($0.formatted(date: .omitted, time: .shortened)). ")
        } ?? ""
        let subtitle = asked + String(localized: "Tap \"I'm OK\" below to let them know you're alright.")
        return HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.title3)
                .foregroundStyle(DailyOKColor.gold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassPill(style: .thin)
        .accessibilityElement(children: .combine)
    }

    /// Lets a receiver who can't act right now defer escalation by 15 minutes
    /// instead of triggering a false alarm to their family.
    private var snoozeButton: some View {
        let left = viewModel.snoozesLeft ?? ReceiverViewModel.maxSnoozes
        let title = left < ReceiverViewModel.maxSnoozes
            ? String(localized: "Remind me in \(ReceiverViewModel.snoozeMinutes) min (\(left) left)")
            : String(localized: "Remind me in \(ReceiverViewModel.snoozeMinutes) min")
        return Button {
            Task { await viewModel.snoozePendingRequest() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSnoozing {
                    ProgressView()
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                }
                Text(title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .disabled(viewModel.isSnoozing)
        .accessibilityLabel(String(localized: "Remind me in \(ReceiverViewModel.snoozeMinutes) minutes. Your family won't be alerted before then. \(left) snoozes left."))
    }

    // MARK: - The button

    private var checkInButton: some View {
        VStack(spacing: 24) {
            Text(greeting)
                .font(.title2)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                // The button below already announces the action; hide the
                // decorative greeting so VoiceOver presents one clear control.
                .accessibilityHidden(true)

            Button {
                DailyOKHaptics.medium()
                Task {
                    await viewModel.performCheckIn()
                    if viewModel.hasCheckedInToday {
                        DailyOKHaptics.success()
                        animateCheckmark()
                        let celebrate = !viewModel.checkInSavedOffline && !isSimpleMode
                        if !viewModel.checkInSavedOffline {
                            // Simple Mode keeps the screen calm — skip confetti.
                            if celebrate { showCelebration = true }
                            // Spoken/audible confirmation for low-vision receivers
                            // (only on a confirmed online check-in).
                            if viewModel.audioConfirmationEnabled { CheckInAudio.confirm() }
                            // No App Store rating prompt here. This screen exists
                            // to be one tap and done; a system dialog two seconds
                            // after "I'm OK" is the opposite. Owners, who use the
                            // app more deeply, are the ones to ask.
                        } else {
                            // Offline-queued: still give low-vision receivers a
                            // distinct spoken cue so a saved-but-not-yet-sent
                            // check-in isn't indistinguishable from silence.
                            if viewModel.audioConfirmationEnabled {
                                CheckInAudio.confirm(String(localized: "Saved. Your check-in will be sent when you're back online."))
                            }
                        }
                        // VoiceOver: the focused button just disappeared. The
                        // overlay announces when it shows; otherwise say it here.
                        if !celebrate {
                            UIAccessibility.post(
                                notification: .announcement,
                                argument: viewModel.checkInSavedOffline
                                    ? String(localized: "Saved on this phone. It will be sent when you're back online.")
                                    : String(localized: "Checked in. Your family has been notified.")
                            )
                        }
                    } else if viewModel.errorMessage != nil {
                        DailyOKHaptics.error()
                    }
                }
            } label: {
                ZStack {
                    // Aurora halo — two soft orbs behind the button for depth.
                    // Hidden in Simple Mode to keep the screen calm. Outside
                    // the tap area (see contentShape below).
                    if !isSimpleMode {
                        Circle()
                            .fill(DailyOKColor.green300.opacity(0.5))
                            .frame(width: effectiveDiameter * 1.4, height: effectiveDiameter * 1.4)
                            .blur(radius: 40)
                            .scaleEffect(isPulsing ? 1.05 : 1.0)
                            .allowsHitTesting(false)
                        Circle()
                            .fill(DailyOKColor.teal.opacity(0.4))
                            .frame(width: effectiveDiameter * 1.2, height: effectiveDiameter * 1.2)
                            .blur(radius: 30)
                            .offset(x: 20, y: 20)
                            .scaleEffect(isPulsing ? 1.08 : 1.0)
                            .allowsHitTesting(false)
                    }

                    // Main button. Darker greens than before (green400→600
                    // put white text at 1.7–3.3:1): green700→800 is ≥5:1
                    // everywhere under the label. Simple Mode is one flat
                    // green700, no highlight.
                    Circle()
                        .fill(buttonFill)
                        .frame(width: effectiveDiameter, height: effectiveDiameter)
                        .overlay {
                            if !isSimpleMode {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        }
                        .shadow(color: DailyOKColor.green800.opacity(0.35), radius: isPulsing ? 24 : 16, y: 8)
                        .scaleEffect(buttonScale)

                    if showCheckmark {
                        Image(systemName: "checkmark")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(.white)
                            .scaleEffect(checkmarkScale)
                            .opacity(checkmarkOpacity)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: tapIconSize))
                                .foregroundStyle(.white)

                            Text(isKidMode && !isSimpleMode ? "I'm OK! 👋" : "I'm OK")
                                .font(.system(size: tapTextSize * (isSimpleMode ? 1.2 : 1.0), weight: .bold))
                                .foregroundStyle(.white)
                                // Keep the label inside the circle at the largest
                                // Dynamic Type sizes instead of overflowing it.
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(maxWidth: effectiveDiameter * 0.8)
                    }
                }
                // Lay out and hit-test the visible circle only; the blurred
                // halo overflows visually but isn't a tap target.
                .frame(width: effectiveDiameter, height: effectiveDiameter)
                .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .disabled(viewModel.isCheckingIn || viewModel.familyId == nil)
            .accessibilityLabel("I'm OK. Tap to let your family know you're okay")
            .accessibilityAddTraits(.isButton)
            .onAppear {
                // No pulsing in Simple Mode — a steady, calm target is easier
                // for senior receivers to focus on and tap.
                guard !reduceMotion, !isSimpleMode else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                    buttonScale = 1.05
                }
            }
            .onDisappear {
                // Reset to base so a later re-insertion of this button (e.g. after
                // Undo re-shows it) actually animates again. Without this,
                // isPulsing/buttonScale stay at their end-state values and the
                // next onAppear animates to the already-current values — a no-op —
                // leaving the button static.
                isPulsing = false
                buttonScale = 1.0
            }

            if viewModel.isCheckingIn {
                ProgressView("Checking in...")
                    .font(.body)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            } else if viewModel.familyId == nil {
                // Before the first load finishes (or offline with nothing
                // cached) a tap did nothing at all.
                ProgressView("Connecting to your family…")
                    .font(.body)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Text("Tap to let your family know you're OK")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                // Redundant with the button's accessibility label.
                .accessibilityHidden(true)
        }
    }

    private var buttonFill: AnyShapeStyle {
        if isSimpleMode { return AnyShapeStyle(DailyOKColor.green700) }
        return AnyShapeStyle(LinearGradient(
            colors: isKidMode
                ? [DailyOKColor.green700, Self.teal700]
                : [DailyOKColor.green700, DailyOKColor.green800],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }

    // MARK: - Status

    private var statusCard: some View {
        let offline = viewModel.checkInSavedOffline
        let headline: String
        if offline {
            headline = String(localized: "Saved — we'll send it when you have signal")
        } else if isKidMode {
            // Whoever watches, not necessarily "parents".
            headline = isSimpleMode
                ? String(localized: "Your family knows you're OK!")
                : String(localized: "Your family knows you're OK! 🎉")
        } else {
            headline = String(localized: "You're all set!")
        }
        let footnote: String
        if offline {
            footnote = viewModel.savedBecauseServerBusy
                ? String(localized: "Daily OK couldn't be reached just now. Your check-in is saved on this phone and will be sent automatically. If it's urgent, call \(ownerLabel).")
                : String(localized: "Saved on this phone. It will be sent as soon as you're back online. If it's urgent, call \(ownerLabel).")
        } else {
            footnote = String(localized: "Your family has been notified")
        }

        return VStack(spacing: 16) {
            Image(systemName: offline ? "clock.fill" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(offline ? DailyOKColor.gold : DailyOKColor.green600)
                .accessibilityHidden(true)

            Text(headline)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

            if let checkIn = viewModel.lastCheckIn {
                Text("Checked in at \(checkIn.checkedInAt.formatted(date: .omitted, time: .shortened))")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            if let nextTime = viewModel.nextCheckInTime {
                Text("Next check-in: \(Self.nextCheckInLabel(nextTime))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            if let actionMessage = viewModel.actionMessage {
                warningText(actionMessage)
            }

            // Undo grace window for an accidental tap (US-IOS048). Visible only
            // while the server-side window is open; clears itself when it lapses.
            if viewModel.undoableUntil != nil, viewModel.lastCheckIn?.isHelpSignal != true {
                Button {
                    DailyOKHaptics.light()
                    Task { await viewModel.undoCheckIn() }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isUndoing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        Text(isKidMode ? "Oops, undo" : "Undo")
                    }
                    .font(.subheadline.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(viewModel.isUndoing)
                .padding(.top, 4)
                .accessibilityHint("Reverses your check-in if you tapped by mistake")
            }

            if let mood = viewModel.selectedMood {
                // Simple Mode shows the words its picker offered ("Not so
                // good"), not the stored mood's label ("Tired").
                let moodWords = isSimpleMode && Mood.standardMoods.contains(mood) ? Self.simpleMoodLabel(mood) : mood.label
                HStack(spacing: 6) {
                    // Simple Mode is an emoji-free, text-only presentation.
                    if !isSimpleMode {
                        Text(mood.emoji)
                    }
                    Text("Feeling \(moodWords.lowercased())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Feeling \(moodWords)")
            } else if viewModel.shouldPromptForMood {
                // Simple Mode used to hide mood entirely — the persona whose
                // "not so good today" matters most could never say it.
                Group {
                    if isSimpleMode { simpleMoodPicker } else { moodPicker }
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(style: .regular, radius: 16, elevation: DailyOKElevation.level2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(offline
            ? String(localized: "Check-in saved. It will be sent when you're back online.")
            : String(localized: "Checked in successfully. Your family has been notified."))
    }

    private var moodPicker: some View {
        VStack(spacing: 10) {
            Text(isKidMode ? "How are you feeling?" : "How are you feeling? (optional)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let moods = isKidMode ? Mood.kidMoods : Mood.standardMoods
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                ForEach(moods, id: \.self) { mood in
                    Button {
                        DailyOKHaptics.light()
                        Task { await viewModel.setMood(mood) }
                    } label: {
                        VStack(spacing: 4) {
                            Text(mood.emoji)
                                .font(.title2)
                            Text(mood.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44) // 44pt min + wrap/scale at large sizes (US-IOS105)
                        .padding(.vertical, 8)
                        .glassPill(style: .thin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feeling \(mood.label)")
                }
            }
        }
    }

    /// Simple Mode: three full-width, text-only choices at body size.
    private var simpleMoodPicker: some View {
        VStack(spacing: 10) {
            Text("How are you feeling today?")
                .font(.body)
                .foregroundStyle(.secondary)
            ForEach([Mood.happy, Mood.neutral, Mood.tired], id: \.self) { mood in
                let label = Self.simpleMoodLabel(mood)
                Button {
                    DailyOKHaptics.light()
                    Task { await viewModel.setMood(mood) }
                } label: {
                    Text(label)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.bordered)
                .tint(DailyOKColor.green700)
                .accessibilityLabel("Feeling \(label)")
            }
        }
    }

    private static func simpleMoodLabel(_ mood: Mood) -> String {
        switch mood {
        case .happy: return String(localized: "Good")
        case .tired: return String(localized: "Not so good")
        default: return String(localized: "Okay")
        }
    }

    // MARK: - Help

    /// What a receiver can send besides "I'm OK". Help used to be reachable
    /// only from a Lock Screen notification that might already be gone.
    private var helpKinds: [ReceiverHelpKind] {
        isKidMode ? [.sos, .pickMeUp, .stayLonger, .callMe] : [.needHelp, .callMe]
    }

    private var helpSection: some View {
        VStack(spacing: 12) {
            Text(isKidMode ? "Need something?" : "Need help?")
                .font(isSimpleMode ? .title3.weight(.semibold) : .headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            ForEach(helpKinds) { kind in
                helpButton(kind)
            }

            if let failure = viewModel.helpFailure {
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Self.helpRed)
                            .accessibilityHidden(true)
                        Text(failure.message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    Button {
                        Task { await viewModel.sendHelp(failure.kind) }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Self.helpRed)
                    .disabled(viewModel.isSendingHelp)
                }
            }

            if viewModel.isSendingHelp {
                ProgressView("Sending…")
            }

            callOwnerButton
            emergencyLine
        }
    }

    private func helpButton(_ kind: ReceiverHelpKind) -> some View {
        Button {
            if kind.isUrgent {
                // Confirmed first: it pages the family with a critical alert.
                pendingHelp = kind
            } else {
                Task { await viewModel.sendHelp(kind) }
            }
        } label: {
            Label(kind.title(owner: viewModel.ownerName), systemImage: kind.icon)
                .font(isSimpleMode ? .title3.weight(.semibold) : .body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: isSimpleMode ? 60 : 50)
        }
        .buttonStyle(.bordered)
        .tint(kind.isUrgent ? Self.helpRed : DailyOKColor.green700)
        .disabled(viewModel.isSendingHelp || viewModel.familyId == nil)
    }

    /// tel: link to the owner, when their number is on file.
    @ViewBuilder
    private var callOwnerButton: some View {
        if let url = Self.telURL(viewModel.ownerPhone) {
            Link(destination: url) {
                Label(viewModel.ownerName.map { String(localized: "Call \($0)") } ?? String(localized: "Call your family"),
                      systemImage: "phone.fill")
                    .font(isSimpleMode ? .title3.weight(.semibold) : .body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: isSimpleMode ? 60 : 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green700)
        }
    }

    @ViewBuilder
    private var emergencyLine: some View {
        if Self.usesNineOneOne, let url = URL(string: "tel:911") {
            Link(destination: url) {
                Text("In an emergency, call 911")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Self.helpRed)
                    .underline()
            }
            .accessibilityHint("Calls emergency services")
        } else {
            Text("In an emergency, call your local emergency number.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private static var usesNineOneOne: Bool {
        ["US", "CA"].contains(Locale.current.region?.identifier ?? "")
    }

    /// "+1 (555) 123-4567" → tel:+15551234567. nil when there's no number.
    nonisolated static func telURL(_ phone: String?) -> URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard digits.filter(\.isNumber).count >= 3 else { return nil }
        return URL(string: "tel:\(digits)")
    }

    /// After "I need help" / "Call me" / SOS: not "You're all set!", no
    /// confetti, no Undo — who was told, whether anyone has it, and a way to
    /// call now.
    private func helpStatusCard(_ help: HelpStatus) -> some View {
        let headline = help.kind == .callMe
            ? String(localized: "We asked \(ownerLabel) to call you")
            : String(localized: "We told \(ownerLabel) you need help")
        return VStack(spacing: 12) {
            Image(systemName: help.kind == .callMe ? "phone.arrow.down.left.fill" : "exclamationmark.bubble.fill")
                .font(.system(size: 44))
                .foregroundStyle(Self.helpRed)
                .accessibilityHidden(true)

            Text(headline)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

            if let sentAt = help.sentAt {
                Text("Sent at \(sentAt.formatted(date: .omitted, time: .shortened))")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let who = help.acknowledgedBy {
                let when = help.acknowledgedAt.map { String(localized: " (\($0.formatted(date: .omitted, time: .shortened)))") } ?? ""
                Label(String(localized: "\(who) is on it") + when, systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DailyOKColor.green700)
            } else {
                Text("Your family got an urgent alert. Keep your phone nearby.")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }

            callOwnerButton

            Text("Tapped this by mistake? Call \(ownerLabel) to let them know you're OK.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(style: .regular, radius: 16, elevation: DailyOKElevation.level2)
        .accessibilityElement(children: .contain)
    }

    /// "Today at 6:00 PM", "Tomorrow at 8:00 AM" or "Monday at 8:00 AM". It
    /// said "Tomorrow" whatever the date — wrong for a second window later
    /// today, or after a weekend with no check-ins.
    static func nextCheckInLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) {
            return String(localized: "Today at \(time)")
        }
        if calendar.isDateInTomorrow(date) {
            return String(localized: "Tomorrow at \(time)")
        }
        let day = date.formatted(.dateTime.weekday(.wide))
        return String(localized: "\(day) at \(time)")
    }

    private func animateCheckmark() {
        showCheckmark = true
        if reduceMotion {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showCheckmark = false
            }
        } else {
            // Ease-out scale + fade; no spring overshoot (craft floor).
            checkmarkScale = 0.8
            withAnimation(.easeOut(duration: 0.25)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showCheckmark = false
            }
        }
    }
}

/// Receiver-facing location choice. The join consent says the family sees
/// "your location if you choose to share it", but iOS never asked, so there
/// was nothing to choose. Only When-In-Use is requested; background tracking
/// stays off.
struct LocationSharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: CLAuthorizationStatus = LocationService.shared.authorizationStatus

    private var isAllowed: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(isAllowed
                             ? String(localized: "On. Help requests include where you are.")
                             : (status == .denied || status == .restricted)
                                ? String(localized: "Off. Location access is turned off for Daily OK.")
                                : String(localized: "Off. Help requests don't include where you are."))
                    } icon: {
                        Image(systemName: isAllowed ? "location.fill" : "location.slash")
                            .foregroundStyle(isAllowed ? DailyOKColor.green700 : .secondary)
                    }

                    if status == .notDetermined {
                        Button("Allow Location") {
                            LocationService.shared.requestPermission()
                        }
                        .tint(DailyOKColor.green700)
                    } else {
                        Button(isAllowed ? "Turn Off in Settings" : "Turn On in Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .tint(DailyOKColor.green700)
                    }
                }

                Section("What your family sees") {
                    Text("When you tap “I need help”, SOS or “Pick me up”, your approximate location (about a city block) goes with it, so your family can find you.")
                    Text("Only while Daily OK is open. It never tracks you in the background.")
                    Text("Everyday check-ins include it only if your family has turned location on for you.")
                }
                .font(.subheadline)
            }
            .navigationTitle("Location Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // The permission prompt and Settings both return here.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { status = LocationService.shared.authorizationStatus }
            }
            .task {
                // The system prompt doesn't background the app on every OS
                // version; poll briefly after asking.
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    status = LocationService.shared.authorizationStatus
                }
            }
        }
    }
}

private extension String {
    /// "your family" → "Your family" at the start of a sentence.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
