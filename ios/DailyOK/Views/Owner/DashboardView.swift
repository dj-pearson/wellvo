import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var notificationBanner = NotificationPermissionBanner()
    @State private var showFirstReceiverWalkthrough = false
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    private static let walkthroughAutoShownKey = "dailyok.firstReceiverWalkthrough.autoShown"

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.receiverCards.isEmpty && viewModel.errorMessage == nil {
                    DashboardSkeletonView()
                        .padding(.top, 8)
                } else if let errorMessage = viewModel.errorMessage, viewModel.receiverCards.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await viewModel.loadDashboard() }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Retry")
                            }
                            .fontWeight(.semibold)
                            .frame(minWidth: 120, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(viewModel.isLoading)
                    }
                    .padding(.top, 80)
                    .padding(.horizontal, 32)
                } else if viewModel.receiverCards.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 16) {
                        // Notification permission banner
                        NotificationPermissionBanner()
                            .task { await notificationBanner.checkPermission() }

                        // Pattern Alerts
                        if !viewModel.alerts.isEmpty {
                            AlertsBannerView(alerts: viewModel.alerts, onDismiss: { alert in
                                Task { await viewModel.dismissAlert(alert) }
                            }, onAcknowledge: { alert, release in
                                Task { await viewModel.acknowledgeAlert(alert, release: release) }
                            })
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                        }

                        // Weekly Summary
                        if let summary = viewModel.weeklySummary {
                            WeeklySummaryCard(summary: summary)
                        }

                        // Today's Timeline
                        if !viewModel.receiverCards.isEmpty {
                            TodayTimelineCard(cards: viewModel.receiverCards)
                        }

                        // Receiver Cards
                        ForEach(Array(viewModel.receiverCards.enumerated()), id: \.element.id) { index, card in
                            ReceiverStatusCardView(card: card, onCheckOn: {
                                Task { await viewModel.sendOnDemandCheckIn(to: card.id) }
                            }, onStandDown: {
                                Task { await viewModel.standDownEscalation(for: card.id) }
                            }, familyId: viewModel.family?.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)).animation(DailyOKMotion.smoothSpring.delay(Double(index) * 0.05)),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding()
                    .animation(DailyOKMotion.smoothSpring, value: viewModel.receiverCards.count)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: alertsPresent ? .alert : .calm))
            .navigationTitle("Dashboard")
            .refreshable { await viewModel.loadDashboard() }
            .task { await viewModel.loadDashboard() }
            // Reload when the app is brought back to the foreground so the owner
            // sees check-ins that landed while the app was suspended (e.g. the
            // receiver tapped "I'm OK" on another device).
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await viewModel.loadDashboard() }
                }
            }
            // Reload when the owner navigates back to the Dashboard tab after
            // visiting another tab. SwiftUI keeps tabs alive, so `.task` only
            // fires once per view lifetime — `onChange` covers the rest.
            .onChange(of: appState.selectedTab) { _, newTab in
                if newTab == .dashboard {
                    Task { await viewModel.loadDashboard() }
                }
            }
            // Present the App Store rating prompt when the view model flags a
            // milestone. The service already gated/throttled the decision; we
            // just show it and reset the flag.
            .onChange(of: viewModel.shouldRequestReview) { _, shouldPrompt in
                guard shouldPrompt else { return }
                requestReview()
                ReviewPromptService.shared.markPrompted()
                viewModel.shouldRequestReview = false
            }
            // Reload when a queued offline check-in syncs (e.g. the owner is
            // also a receiver on the same device) so the card flips from
            // Pending to Checked In without waiting for the next foreground.
            .onReceive(NotificationCenter.default.publisher(for: OfflineCheckInService.didSyncCheckIns)) { _ in
                Task { await viewModel.loadDashboard() }
            }
            // Auto-present the first-receiver walkthrough once when the owner
            // lands on an empty Dashboard for the first time. The CTA on the
            // empty state stays available for re-opens.
            .onChange(of: viewModel.isLoading) { _, loading in
                guard !loading,
                      viewModel.errorMessage == nil,
                      viewModel.receiverCards.isEmpty,
                      appState.currentUserRole == .owner,
                      !UserDefaults.standard.bool(forKey: Self.walkthroughAutoShownKey)
                else { return }
                UserDefaults.standard.set(true, forKey: Self.walkthroughAutoShownKey)
                showFirstReceiverWalkthrough = true
            }
            .sheet(isPresented: $showFirstReceiverWalkthrough) {
                FirstReceiverWalkthroughView {
                    await viewModel.loadDashboard()
                }
                .dailyokGlassSheet(style: .regular)
            }
        }
    }

    private var alertsPresent: Bool {
        !viewModel.alerts.isEmpty || viewModel.receiverCards.contains(where: { $0.status == .missed })
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "person.badge.plus",
            title: "Add Your First Family Member",
            message: "We'll walk you through it — takes about a minute.",
            primaryActionLabel: appState.currentUserRole == .owner ? "Get Started" : nil,
            onPrimaryAction: appState.currentUserRole == .owner ? {
                DailyOKHaptics.selection()
                showFirstReceiverWalkthrough = true
            } : nil
        )
    }
}

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    let summary: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack(spacing: 20) {
                StatBubble(
                    value: "\(Int(summary.consistencyPercentage))%",
                    label: "Consistency",
                    color: summary.consistencyPercentage >= 80 ? .green : summary.consistencyPercentage >= 50 ? .yellow : .red
                )

                StatBubble(
                    value: summary.averageCheckInTime,
                    label: "Avg Time",
                    color: .blue
                )

                StatBubble(
                    value: "\(summary.totalCheckIns)/\(summary.totalExpected)",
                    label: "Check-Ins",
                    color: .green
                )
            }

            // Mood breakdown
            if !summary.moodBreakdown.isEmpty {
                HStack(spacing: 12) {
                    Text("Moods:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(summary.moodBreakdown.keys), id: \.self) { mood in
                        HStack(spacing: 2) {
                            Text(mood.emoji)
                            Text("\(summary.moodBreakdown[mood] ?? 0)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("\(mood.label): \(summary.moodBreakdown[mood] ?? 0)")
                    }
                }
            }
        }
        .padding()
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level2)
    }
}

struct StatBubble: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(DailyOKMotion.smoothSpring, value: value)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Today's Timeline Card

struct TodayTimelineCard: View {
    let cards: [ReceiverStatusCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Timeline")
                .font(.headline)

            ForEach(cards) { card in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(card.status.color)
                            .frame(width: 10, height: 10)

                        Image(systemName: timelineStatusIcon(for: card))
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)

                    Text(card.name)
                        .font(.subheadline)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: timelineStatusIcon(for: card))
                            .font(.caption2)

                        if let time = card.checkedInTime {
                            Text(time.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(card.status.label)
                                .font(.caption)
                                .foregroundStyle(card.status.color)
                        }
                    }

                    // Timeline bar
                    timelineBar(for: card)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(card.name): \(card.checkedInTime != nil ? "checked in at \(card.checkedInTime!.formatted(date: .omitted, time: .shortened))" : card.status.label)")
            }
        }
        .padding()
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level2)
    }

    private func timelineStatusIcon(for card: ReceiverStatusCard) -> String {
        if card.checkedInTime != nil {
            return "checkmark.circle"
        }
        // Use the card's status label to differentiate pending vs missed
        let label = card.status.label.lowercased()
        if label.contains("miss") {
            return "xmark.circle"
        }
        return "clock"
    }

    private func timelineBar(for card: ReceiverStatusCard) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                if let time = card.checkedInTime {
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: time)
                    let minute = calendar.component(.minute, from: time)
                    let progress = CGFloat(hour * 60 + minute) / (24 * 60)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(card.status.color)
                        .frame(width: max(4, geometry.size.width * progress), height: 4)
                }
            }
        }
        .frame(width: 60, height: 4)
    }
}

// MARK: - Receiver Status Card

struct ReceiverStatusCardView: View {
    let card: ReceiverStatusCard
    var isReadOnly: Bool = false
    let onCheckOn: () -> Void
    var onStandDown: (() -> Void)? = nil
    /// US-IOS016: family the receiver belongs to, so the card can open the
    /// shared care-notes timeline. Nil hides the notes affordance.
    var familyId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Avatar
                Circle()
                    .fill(card.status.color.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: card.status.icon)
                            .font(.title2)
                            .foregroundStyle(card.status.color)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(card.name)
                            .font(.headline)

                        // Notification status indicator
                        if !card.hasNotificationsEnabled {
                            Image(systemName: "bell.slash.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .help("Notifications not enabled")
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: card.status.icon)
                            .font(.caption)
                        Text(card.status.label)
                            .font(.subheadline)
                    }
                    .foregroundStyle(card.status.color)
                }

                Spacer()

                // Streak + 7-day consistency chips. Render only when meaningful
                // (StreakChip auto-hides below 2 days; ConsistencyChip auto-hides
                // for the .none tier i.e. <50% consistency). Falls back to the
                // big day-count when neither chip would show, so high-streak +
                // low-consistency users still see their headline number.
                let badge = Streaks.badge(consistencyPercent: card.consistencyPercent)
                if card.streak >= 2 || badge != .none {
                    VStack(alignment: .trailing, spacing: 4) {
                        StreakChip(streakDays: card.streak)
                        ConsistencyChip(badge: badge)
                    }
                } else {
                    VStack(spacing: 2) {
                        Text("\(card.streak)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(DailyOKColor.green500)
                            .contentTransition(.numericText(value: Double(card.streak)))
                            .animation(DailyOKMotion.smoothSpring, value: card.streak)
                        Text("day streak")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Notification warning (owner-only)
            if !isReadOnly && !card.hasNotificationsEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("\(card.name) hasn't enabled notifications. They may miss check-in reminders.")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Last check-in time
            if let lastCheckIn = card.lastCheckIn {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("Last check-in: \(lastCheckIn.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            // Mood indicator
            if let mood = card.mood {
                HStack {
                    Text("Mood:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(mood.emoji)
                        .font(.body)
                    Text(mood.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mood: \(mood.label)")
            }

            // Location label (kid mode)
            if let locationLabel = card.locationLabel, !locationLabel.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("At: \(locationLabelDisplay(locationLabel))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Location: \(locationLabelDisplay(locationLabel))")
            }

            // Kid response type
            if let kidResponse = card.kidResponseType, !kidResponse.isEmpty {
                kidResponseBadge(kidResponse)
            }

            // Escalation in progress (owner-only) — show the receiver hasn't
            // responded and offer a "stand down" so the owner can stop the alerts
            // after reaching them another way (e.g. a phone call).
            if !isReadOnly, card.status != .checkedIn, card.escalationStep >= 1 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.and.waves.left.and.right.fill")
                            .font(.caption)
                        Text(card.status == .missed
                             ? "\(card.name) didn't check in — alerts were sent."
                             : "Escalating — \(card.name) hasn't responded yet (step \(card.escalationStep) of 3).")
                            .font(.caption)
                    }
                    .foregroundStyle(card.status == .missed ? .red : .orange)

                    if let onStandDown {
                        Button {
                            onStandDown()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.shield")
                                Text("I've reached them — stand down")
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .accessibilityHint("Stops the escalation reminders and alerts for \(card.name)")
                    }
                }
                .padding(8)
                .background((card.status == .missed ? Color.red : Color.orange).opacity(0.1))
                .cornerRadius(8)
            }

            // Check on button (owner-only) — always available so a parent can
            // ping the receiver on demand even after today's scheduled check-in
            // (e.g. "kid is out playing, want another update right now").
            if !isReadOnly {
                let alreadyChecked = card.status == .checkedIn
                Button {
                    onCheckOn()
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text(alreadyChecked ? "Request another update" : "Check on \(card.name)")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(alreadyChecked ? .blue : .orange)
                .accessibilityLabel(alreadyChecked ? "Request another update from \(card.name)" : "Check on \(card.name)")
                .accessibilityHint("Sends an immediate check-in notification")
            }

            // One-tap reach the receiver directly — useful for any caregiver
            // (owner or viewer) when a check-in looks off.
            ContactQuickActions(name: card.name, phone: card.phone)

            // Shared care notes / timeline (owner + viewers). US-IOS016.
            if let familyId {
                NavigationLink {
                    CareNotesView(familyId: familyId, receiverId: card.id, receiverName: card.name)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                        Text("Care notes")
                        if card.noteCount > 0 {
                            Text("\(card.noteCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(DailyOKColor.green.opacity(0.2), in: Capsule())
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                }
                .accessibilityHint("Open the shared care notes for \(card.name).")
            }
        }
        .padding()
        .glassCard(style: .regular, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.name), \(card.status.label), \(card.streak) day streak")
    }
}

private func moodEmoji(_ mood: Mood) -> String {
    mood.emoji
}

private func locationLabelDisplay(_ rawValue: String) -> String {
    if let label = LocationLabel(rawValue: rawValue) {
        return label.label
    }
    return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
}

private func kidResponseBadge(_ rawValue: String) -> some View {
    let config: (text: String, color: Color)
    switch rawValue {
    case KidResponseType.pickingMeUp.rawValue:
        config = ("Wants pickup", .orange)
    case KidResponseType.canStayLonger.rawValue:
        config = ("Wants to stay longer", .blue)
    case KidResponseType.sos.rawValue:
        config = ("SOS!", .red)
    default:
        config = (rawValue, .gray)
    }

    return HStack(spacing: 4) {
        Image(systemName: config.color == .red ? "exclamationmark.triangle.fill" : "bubble.left.fill")
            .font(.caption2)
        Text(config.text)
            .font(.caption)
            .fontWeight(.medium)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(config.color, in: Capsule())
    .accessibilityLabel("Kid response: \(config.text)")
}

// MARK: - Pattern Alerts Banner

struct AlertsBannerView: View {
    let alerts: [DailyOKAlert]
    let onDismiss: (DailyOKAlert) -> Void
    /// US-IOS013: acknowledge (false) / release (true) so co-caregivers can
    /// coordinate. Optional so existing call sites that don't pass it still work.
    var onAcknowledge: ((DailyOKAlert, Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            ForEach(alerts) { alert in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: alert.type == "time_drift" ? "clock.badge.exclamationmark" : "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(alert.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let driftHours = alert.data?["drift_hours"] as? Double {
                                Text("Shifted by \(String(format: "%.1f", driftHours)) hours")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }

                        Spacer()

                        Button {
                            onDismiss(alert)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if let onAcknowledge {
                        acknowledgementRow(for: alert, onAcknowledge: onAcknowledge)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous)
                        .fill(DailyOKColor.warning.opacity(alert.isAcknowledged ? 0.06 : 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous)
                                .strokeBorder(DailyOKColor.warning.opacity(alert.isAcknowledged ? 0.15 : 0.3), lineWidth: 0.75)
                        )
                )
                .opacity(alert.isAcknowledged ? 0.7 : 1)
            }
        }
    }

    @ViewBuilder
    private func acknowledgementRow(for alert: DailyOKAlert,
                                    onAcknowledge: @escaping (DailyOKAlert, Bool) -> Void) -> some View {
        if alert.isAcknowledged {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(DailyOKColor.green)
                let who = alert.acknowledgedByName ?? "A caregiver"
                let when = alert.acknowledgedAt?.formatted(date: .omitted, time: .shortened) ?? ""
                Text(when.isEmpty ? "Handled by \(who)" : "Handled by \(who) at \(when)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Release") { onAcknowledge(alert, true) }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(DailyOKColor.green)
            }
            .accessibilityElement(children: .combine)
        } else {
            Button {
                onAcknowledge(alert, false)
            } label: {
                Label("I've got this", systemImage: "hand.raised.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green)
            .accessibilityHint("Lets other caregivers know you're handling this so they don't all respond at once.")
        }
    }
}
