import SwiftUI

struct ReceiverHomeView: View {
    @StateObject private var viewModel = ReceiverViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var buttonScale: CGFloat = 1.0
    @State private var isPulsing = false
    @State private var showCheckmark = false
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var checkmarkOpacity: Double = 0.0
    @State private var showSignOutConfirmation = false
    @State private var showCelebration = false
    @ScaledMetric(relativeTo: .largeTitle) private var buttonDiameter: CGFloat = 200
    @ScaledMetric(relativeTo: .title) private var tapIconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var tapTextSize: CGFloat = 28

    private var isKidMode: Bool {
        viewModel.receiverMode == .kid
    }

    /// Senior Simple Mode: extra-large, calm, high-contrast, low-clutter.
    private var isSimpleMode: Bool {
        viewModel.simpleMode
    }

    private var effectiveDiameter: CGFloat {
        isSimpleMode ? buttonDiameter * 1.18 : buttonDiameter
    }

    var body: some View {
        ZStack {
            AmbientBackground(tone: viewModel.hasCheckedInToday ? .calm : .warm)

            ScrollView {
                VStack(spacing: 24) {
                    NotificationPermissionBanner()
                        .padding(.horizontal)

                    if viewModel.isOffline {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                            Text(viewModel.pendingOfflineCount > 0
                                 ? "Offline — \(viewModel.pendingOfflineCount) check-in(s) will sync when reconnected"
                                 : "You're offline")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DailyOKColor.warning)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassPill(style: .thin)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .accessibilityLabel(viewModel.pendingOfflineCount > 0
                            ? "Offline. \(viewModel.pendingOfflineCount) check-ins pending sync."
                            : "You are offline")
                    }

                    Spacer().frame(height: 20)

                    // Streak + 7-day consistency header chips. Both chips
                    // self-hide when there isn't enough history (streak < 2,
                    // consistency < 50%), so first-day receivers see no header.
                    if !isSimpleMode && (viewModel.streakDays >= 2 || Streaks.badge(consistencyPercent: viewModel.consistencyPercent) != .none) {
                        HStack(spacing: 8) {
                            StreakChip(streakDays: viewModel.streakDays)
                            ConsistencyChip(badge: Streaks.badge(consistencyPercent: viewModel.consistencyPercent))
                        }
                    }

                    if viewModel.hasCheckedInToday {
                        statusCard.padding(.horizontal)
                    } else {
                        if viewModel.hasPendingRequest {
                            pendingRequestBanner.padding(.horizontal)
                        }
                        checkInButton
                    }

                    if let errorMessage = viewModel.errorMessage {
                        VStack(spacing: 12) {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)

                            Button {
                                Task { await viewModel.performCheckIn() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Try Again")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(minWidth: 120, minHeight: 36)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        .padding(.horizontal)
                    }

                    Spacer().frame(height: 20)
                }
                .padding()
            }

            // Discreet menu — sign out + link into iOS notification settings.
            // Placed top-right as an overlay so it stays accessible from either
            // the check-in button state or the "all set" state without
            // cluttering the main content.
            VStack {
                HStack {
                    Spacer()
                    Menu {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Notification Settings", systemImage: "bell.badge")
                        }
                        Button(role: .destructive) {
                            showSignOutConfirmation = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More options")
                }
                Spacer()
            }
            .padding(.horizontal, 8)

            CelebrationOverlay(isVisible: $showCelebration) {
                showCelebration = false
            }
        }
        .task { await viewModel.loadStatus() }
        // If a silent push request arrived while the app was backgrounded, or the
        // user checked in on another device, re-fetch on foreground so the home
        // screen reflects the true state instead of stale "please check in" UI.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.loadStatus() }
            }
        }
        // When queued offline check-ins sync to the server, reload so the
        // "you're all set" card reflects the now-persisted check-in (or
        // vice-versa if the server rejected it).
        .onReceive(NotificationCenter.default.publisher(for: OfflineCheckInService.didSyncCheckIns)) { _ in
            Task { await viewModel.loadStatus() }
        }
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                DailyOKHaptics.warning()
                Task { await authViewModel.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop receiving check-in notifications until you sign back in.")
        }
    }

    private var pendingRequestBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.title3)
                .foregroundStyle(DailyOKColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(isKidMode ? "Your family wants to hear from you!" : "Your family is waiting")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Tap \"I'm OK\" below to let them know you're alright.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassPill(style: .thin)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your family is waiting for you to check in.")
    }

    private var checkInButton: some View {
        VStack(spacing: 24) {
            Text("Good morning!")
                .font(.title2)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

            Button {
                DailyOKHaptics.medium()
                Task {
                    await viewModel.performCheckIn()
                    if viewModel.hasCheckedInToday {
                        DailyOKHaptics.success()
                        animateCheckmark()
                        if viewModel.errorMessage == nil && !viewModel.isOffline {
                            // Simple Mode keeps the screen calm — skip confetti.
                            if !isSimpleMode { showCelebration = true }
                            // Spoken/audible confirmation for low-vision receivers
                            // (only on a confirmed online check-in).
                            if viewModel.audioConfirmationEnabled { CheckInAudio.confirm() }
                            // A confirmed, online check-in is a genuine positive
                            // moment. Ask for an App Store rating only if the user
                            // has earned it — the service handles the threshold and
                            // throttling, and lets the celebration play first.
                            if ReviewPromptService.shared.registerSuccessfulCheckIn() {
                                try? await Task.sleep(for: .seconds(2))
                                requestReview()
                                ReviewPromptService.shared.markPrompted()
                            }
                        }
                    } else if viewModel.errorMessage != nil {
                        DailyOKHaptics.error()
                    }
                }
            } label: {
                ZStack {
                    // Aurora halo — two soft orbs behind the button for premium
                    // depth. Hidden in Simple Mode to keep the screen calm and
                    // high-contrast for senior receivers.
                    if !isSimpleMode {
                        Circle()
                            .fill(DailyOKColor.green300.opacity(0.5))
                            .frame(width: buttonDiameter * 1.4, height: buttonDiameter * 1.4)
                            .blur(radius: 40)
                            .scaleEffect(isPulsing ? 1.05 : 1.0)
                        Circle()
                            .fill(DailyOKColor.teal.opacity(0.4))
                            .frame(width: buttonDiameter * 1.2, height: buttonDiameter * 1.2)
                            .blur(radius: 30)
                            .offset(x: 20, y: 20)
                            .scaleEffect(isPulsing ? 1.08 : 1.0)
                    }

                    // Main button — brand gradient with a glass highlight on top
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isKidMode
                                    ? [DailyOKColor.green400, DailyOKColor.teal]
                                    : [DailyOKColor.green400, DailyOKColor.green600],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: effectiveDiameter, height: effectiveDiameter)
                        .overlay(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.0)],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: DailyOKColor.green600.opacity(0.45), radius: isPulsing ? 28 : 18, y: 8)
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

                            Text(isKidMode ? "I'm OK! 👋" : "I'm OK")
                                .font(.system(size: tapTextSize, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .buttonStyle(.pressable)
            .disabled(viewModel.isCheckingIn)
            .accessibilityLabel("Tap to check in and let your family know you're okay")
            .onAppear {
                // No pulsing in Simple Mode — a steady, calm target is easier
                // for senior receivers to focus on and tap.
                guard !reduceMotion, !isSimpleMode else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                    buttonScale = 1.05
                }
            }

            if viewModel.isCheckingIn {
                ProgressView("Checking in...")
                    .font(.body)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Text("Tap to let your family know you're OK")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }

    private var statusCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: reduceMotion ? false : viewModel.hasCheckedInToday)
                .accessibilityHidden(true)

            Text(isKidMode ? "Awesome! Your parents know you're OK! 🎉" : "You're all set!")
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
                Text("Next check-in: Tomorrow at \(nextTime.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Text("Your family has been notified")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            if let mood = viewModel.selectedMood {
                HStack(spacing: 6) {
                    // Simple Mode is an emoji-free, text-only presentation.
                    if !isSimpleMode {
                        Text(mood.emoji)
                    }
                    Text("Feeling \(mood.label.lowercased())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Feeling \(mood.label)")
            } else if viewModel.shouldPromptForMood && !isSimpleMode {
                moodPicker.padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(style: .regular, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .overlay(
            RoundedRectangle(cornerRadius: DailyOKGlass.radiusLarge, style: .continuous)
                .strokeBorder(DailyOKColor.green300.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Checked in successfully. Your family has been notified.")
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
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .glassPill(style: .thin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feeling \(mood.label)")
                }
            }
        }
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                checkmarkScale = 1.2
                checkmarkOpacity = 1.0
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.2)) {
                checkmarkScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showCheckmark = false
            }
        }
    }
}
