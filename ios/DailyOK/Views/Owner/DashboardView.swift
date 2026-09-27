import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showFirstReceiverWalkthrough = false
    /// A stand-down asked for from the Live Activity, waiting for the owner to
    /// confirm it here (never acted on straight from the URL).
    @State private var standDownPrompt: ReceiverStatusCard?
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    private static let walkthroughAutoShownKey = "dailyok.firstReceiverWalkthrough.autoShown"

    /// Owners act; viewers (co-caregivers) see everything but the owner-only
    /// controls, which the server rejects for them anyway (403).
    private var isOwner: Bool { appState.currentUserRole == .owner }

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollViewReader { proxy in
                    content(proxy: proxy)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: alertsPresent ? .alert : .calm))
            .navigationTitle("Dashboard")
            .refreshable { await viewModel.loadDashboard() }
            .task {
                await viewModel.loadDashboard()
                resolvePendingStandDown()
            }
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
            // Live Activity "Stand down": load fresh status, then confirm.
            .onChange(of: appState.pendingStandDown) { _, pending in
                guard pending != nil else { return }
                Task {
                    await viewModel.loadDashboard()
                    resolvePendingStandDown()
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
            // Auto-present the first-receiver walkthrough once per OWNER
            // ACCOUNT when they land on an empty Dashboard for the first time
            // (the flag used to be device-wide, so a second owner on the same
            // phone never saw it). The CTA on the empty state stays available.
            .onChange(of: viewModel.isLoading) { _, loading in
                guard !loading,
                      viewModel.errorMessage == nil,
                      viewModel.receiverCards.isEmpty,
                      isOwner,
                      let userId = viewModel.currentUserId
                else { return }
                let key = "\(Self.walkthroughAutoShownKey).\(userId.uuidString)"
                // One-time shim (CLAUDE.md §C): builds before the per-user key
                // stored a device-wide flag. Carry it over to the first owner
                // seen after the upgrade instead of re-showing the walkthrough.
                if UserDefaults.standard.bool(forKey: Self.walkthroughAutoShownKey) {
                    UserDefaults.standard.removeObject(forKey: Self.walkthroughAutoShownKey)
                    UserDefaults.standard.set(true, forKey: key)
                }
                guard !UserDefaults.standard.bool(forKey: key) else { return }
                UserDefaults.standard.set(true, forKey: key)
                showFirstReceiverWalkthrough = true
            }
            .sheet(isPresented: $showFirstReceiverWalkthrough) {
                FirstReceiverWalkthroughView {
                    await viewModel.loadDashboard()
                }
                .dailyokGlassSheet(style: .regular)
            }
            // Failed owner ACTIONS (check-on, stand-down, dismiss/acknowledge)
            // must be visible — a silently-failed stand-down can't read as
            // success (US-IOS083). Background refresh failures do NOT come
            // here; they show as the inline "showing status from …" strip.
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil && !viewModel.receiverCards.isEmpty },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                ),
                presenting: viewModel.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .confirmationDialog(
                "Stop alerts for \(standDownPrompt?.name ?? "")?",
                isPresented: Binding(
                    get: { standDownPrompt != nil },
                    set: { if !$0 { standDownPrompt = nil } }
                ),
                titleVisibility: .visible,
                presenting: standDownPrompt
            ) { card in
                Button("Stop alerts", role: .destructive) {
                    DailyOKHaptics.warning()
                    Task { await confirmStandDown(card) }
                }
                Button("Keep alerting", role: .cancel) {}
            } message: { card in
                Text("Only do this if you've confirmed \(card.name) is OK. It stops the reminders and caregiver alerts.")
            }
        }
    }

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        if viewModel.isLoading && viewModel.receiverCards.isEmpty && viewModel.errorMessage == nil {
            DashboardSkeletonView()
                .padding(.top, 8)
        } else if let errorMessage = viewModel.errorMessage, viewModel.receiverCards.isEmpty {
            loadErrorState(errorMessage)
        } else if viewModel.receiverCards.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 16) {
                // Notification permission banner — self-contained; it
                // checks permission on appear and on foreground.
                NotificationPermissionBanner()

                if let refreshError = viewModel.refreshError {
                    StaleDataStrip(
                        lastUpdatedAt: viewModel.lastUpdatedAt,
                        detail: refreshError,
                        isLoading: viewModel.isLoading
                    ) {
                        Task { await viewModel.loadDashboard() }
                    }
                }

                DashboardHeadline(cards: viewModel.receiverCards) { id in
                    withAnimation(DailyOKMotion.smoothSpring) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }

                // Alerts — urgent (need help / call me / geofence) first.
                if !viewModel.alerts.isEmpty {
                    AlertsBannerView(
                        alerts: viewModel.alerts,
                        receivers: viewModel.receiverCards,
                        currentUserId: viewModel.currentUserId,
                        isOwner: isOwner,
                        onDismiss: { alert in
                            Task { await viewModel.dismissAlert(alert) }
                        },
                        onAcknowledge: { alert, release in
                            Task { await viewModel.acknowledgeAlert(alert, release: release) }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }

                // A timeline only earns its space with several receivers; with
                // one or two it repeats the cards right below it.
                if viewModel.receiverCards.count >= 3 {
                    TodayTimelineCard(cards: viewModel.receiverCards)
                }

                // Receiver cards, most urgent first.
                ForEach(Array(viewModel.receiverCards.enumerated()), id: \.element.id) { index, card in
                    ReceiverStatusCardView(
                        card: card,
                        isReadOnly: !isOwner,
                        onCheckOn: {
                            await viewModel.sendOnDemandCheckIn(to: card.id)
                        },
                        onStandDown: {
                            await viewModel.standDownEscalation(for: card.id)
                        },
                        familyId: viewModel.family?.id,
                        handledBy: handledBy(for: card),
                        settingsMember: isOwner ? viewModel.receiverMembers[card.id] : nil
                    )
                    .id(card.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)).animation(DailyOKMotion.smoothSpring.delay(Double(index) * 0.05)),
                        removal: .opacity
                    ))
                }

                // The week in review sits below today's answers.
                if let summary = viewModel.weeklySummary {
                    WeeklySummaryCard(summary: summary)
                }
            }
            .padding()
            .animation(DailyOKMotion.smoothSpring, value: viewModel.receiverCards.count)
        }
    }

    private func loadErrorState(_ errorMessage: String) -> some View {
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
            .tint(DailyOKColor.green700)
            .disabled(viewModel.isLoading)
        }
        .padding(.top, 80)
        .padding(.horizontal, 32)
    }

    /// Needs attention: drives the alert background tone.
    private var alertsPresent: Bool {
        viewModel.alerts.contains(where: { DashboardViewModel.isUrgent($0) && !$0.isAcknowledged })
            || viewModel.receiverCards.contains(where: \.needsAttention)
    }

    /// Who has claimed today's urgent alert for this receiver, if anyone, so a
    /// "needs help" card can say it's being handled.
    private func handledBy(for card: ReceiverStatusCard) -> String? {
        guard card.status == .needsHelp else { return nil }
        return viewModel.alerts.first(where: {
            $0.receiverId == card.id && DashboardViewModel.isUrgent($0) && $0.isAcknowledged
        })?.acknowledgedByName
    }

    /// Match a Live Activity stand-down to a receiver who is actually
    /// escalating in the loaded family, then ask. Anything else (another
    /// family, nothing escalating, not the owner) is explained, not acted on.
    private func resolvePendingStandDown() {
        guard let pending = appState.pendingStandDown else { return }
        appState.pendingStandDown = nil
        guard isOwner else {
            appState.deepLinkOutcome = AppState.DeepLinkOutcome(
                title: "Only the owner can stop alerts",
                message: "The family owner can stand down alerts once they've reached them.",
                isFailure: true
            )
            return
        }
        guard viewModel.family?.id == pending.familyId,
              let card = viewModel.receiverCards.first(where: { $0.id == pending.receiverId }),
              card.escalationStep >= 1 || (card.status == .missed && !card.stoodDown)
        else {
            appState.deepLinkOutcome = AppState.DeepLinkOutcome(
                title: "Nothing to stand down",
                message: "There's no alert running for this person right now.",
                isFailure: false
            )
            return
        }
        standDownPrompt = card
    }

    private func confirmStandDown(_ card: ReceiverStatusCard) async {
        if await viewModel.standDownEscalation(for: card.id) {
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Alerts stopped for \(card.name)"))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isOwner {
            EmptyStateView(
                systemImage: "person.badge.plus",
                title: "Add Your First Family Member",
                message: "We'll walk you through it — takes about a minute.",
                primaryActionLabel: "Get Started",
                onPrimaryAction: {
                    DailyOKHaptics.selection()
                    showFirstReceiverWalkthrough = true
                }
            )
        } else {
            // Viewers can't add anyone — don't promise a walkthrough they can
            // never reach.
            EmptyStateView(
                systemImage: "person.2",
                title: "No One to Check On Yet",
                message: "The family owner adds the people you check on. They'll show up here as soon as they're added."
            )
        }
    }
}

// MARK: - Headline

/// One sentence answering "is everyone OK?" before anything else, with a tap
/// that jumps to the person who needs attention.
struct DashboardHeadline: View {
    let cards: [ReceiverStatusCard]
    let onSelect: (UUID) -> Void

    private struct Line {
        let text: String
        let icon: String
        let color: Color
        let target: UUID?
    }

    private var line: Line {
        if let c = cards.first(where: { $0.status == .needsHelp }) {
            return Line(text: "\(c.name): \(c.statusDetail ?? c.helpKind?.label ?? "needs help")",
                        icon: "exclamationmark.bubble.fill", color: .red, target: c.id)
        }
        if let c = cards.first(where: { $0.status == .missed && !$0.stoodDown }) {
            return Line(text: "\(c.name) didn't check in — caregivers were alerted",
                        icon: "exclamationmark.circle.fill", color: .red, target: c.id)
        }
        if let c = cards.first(where: { $0.status == .pending && !$0.stoodDown && $0.escalationStep >= 1 }) {
            return Line(text: "\(c.name) hasn't answered yet — reminders are going out",
                        icon: "bell.and.waves.left.and.right.fill", color: ReceiverCheckInStatus.pending.color, target: c.id)
        }
        let waiting = cards.filter { $0.status == .pending && !$0.stoodDown }
        if waiting.count == 1, let c = waiting.first {
            return Line(text: "Waiting on \(c.name)", icon: "clock.fill",
                        color: ReceiverCheckInStatus.pending.color, target: c.id)
        }
        if waiting.count > 1 {
            return Line(text: "Waiting on \(waiting.count) people", icon: "clock.fill",
                        color: ReceiverCheckInStatus.pending.color, target: waiting.first?.id)
        }
        let checkedIn = cards.filter { $0.status == .checkedIn }.count
        if checkedIn == cards.count {
            return Line(text: cards.count == 1 ? "\(cards[0].name) checked in today" : "Everyone's checked in today",
                        icon: "checkmark.circle.fill", color: DailyOKColor.green600, target: nil)
        }
        return Line(text: "\(checkedIn) of \(cards.count) checked in · nothing overdue",
                    icon: "checkmark.circle", color: DailyOKColor.green600, target: nil)
    }

    var body: some View {
        let current = line
        let hint: String = current.target != nil ? String(localized: "Shows their card") : ""
        Button {
            if let target = current.target { onSelect(target) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: current.icon)
                    .font(.title3)
                    .foregroundStyle(current.color)
                Text(current.text)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if current.target != nil {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(current.target == nil)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(hint)
    }
}

/// Quiet, non-modal notice that the cards are from an earlier load.
struct StaleDataStrip: View {
    let lastUpdatedAt: Date?
    let detail: String
    let isLoading: Bool
    let onRetry: () -> Void

    var body: some View {
        Button(action: onRetry) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "wifi.exclamationmark")
                }
                Group {
                    if let lastUpdatedAt {
                        Text("Couldn't refresh — showing status from \(lastUpdatedAt.formatted(date: .omitted, time: .shortened)). Tap to retry.")
                    } else {
                        Text("Couldn't refresh. Tap to retry.")
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(DailyOKColor.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityHint(detail)
    }
}

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let summary: WeeklySummary

    private var consistencyColor: Color {
        guard summary.hasData else { return .secondary }
        let status: ReceiverCheckInStatus = summary.consistencyPercentage >= 80
            ? .checkedIn : summary.consistencyPercentage >= 50 ? .pending : .missed
        return status.color(increasedContrast: contrast == .increased)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack(spacing: 20) {
                StatBubble(
                    value: summary.hasData ? "\(Int(summary.consistencyPercentage))%" : "—",
                    label: "Consistency",
                    color: consistencyColor,
                    qualifier: summary.hasData
                        ? (summary.consistencyPercentage >= 80 ? "Good" : summary.consistencyPercentage >= 50 ? "Fair" : "Low")
                        : "Not enough data yet"
                )

                StatBubble(
                    value: summary.averageCheckInTime,
                    label: "Avg Time",
                    color: .blue
                )

                StatBubble(
                    value: summary.hasData ? "\(summary.totalCheckIns)/\(summary.totalExpected)" : "—",
                    label: "Days",
                    color: consistencyColor
                )
            }

            // One person slipping must not hide inside a family average.
            if !summary.lagging.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.lagging, id: \.self) { line in
                        Label(line, systemImage: "arrow.down.right.circle")
                            .font(.caption)
                    }
                }
                .foregroundStyle(ReceiverCheckInStatus.pending.color(increasedContrast: contrast == .increased))
            }

            // Mood breakdown
            if !summary.moodBreakdown.isEmpty {
                HStack(spacing: 12) {
                    Text("Moods:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Iterate in the enum's declared order, not the dictionary's
                    // nondeterministic key order (which reshuffled the mood chips
                    // on every refresh/redraw).
                    ForEach(Mood.allCases.filter { summary.moodBreakdown[$0] != nil }, id: \.self) { mood in
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
    /// Optional plain-language qualifier (e.g. "Good"/"Fair"/"Low") so status
    /// isn't conveyed by color alone — important for color-blind users and in
    /// bright sunlight.
    var qualifier: String? = nil

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
            if let qualifier {
                Text(qualifier)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(qualifier == nil ? "\(label): \(value)" : "\(label): \(value), \(qualifier ?? "")")
    }
}

// MARK: - Today's Timeline Card

struct TodayTimelineCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let cards: [ReceiverStatusCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Timeline")
                .font(.headline)

            ForEach(cards) { card in
                HStack(spacing: 12) {
                    Image(systemName: card.status.icon)
                        .font(.subheadline)
                        .foregroundStyle(card.status.color(increasedContrast: contrast == .increased))
                        .frame(width: 20)
                        .accessibilityHidden(true)

                    Text(card.name)
                        .font(.subheadline)

                    Spacer()

                    if card.status == .checkedIn, let time = card.checkedInTime {
                        Text(ReceiverTime.format(time, timezone: card.timezone))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(card.status.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(card.status.color(increasedContrast: contrast == .increased))
                    }

                    // Timeline bar — position within the RECEIVER's day.
                    timelineBar(for: card)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(card.name): \(card.status.label). \(card.statusDetail ?? "")")
            }
        }
        .padding()
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level2)
    }

    private func timelineBar(for card: ReceiverStatusCard) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                if let time = card.checkedInTime {
                    let calendar = Calendar.forTimezone(card.timezone)
                    let hour = calendar.component(.hour, from: time)
                    let minute = calendar.component(.minute, from: time)
                    let progress = CGFloat(hour * 60 + minute) / (24 * 60)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(card.status.color(increasedContrast: contrast == .increased))
                        .frame(width: max(4, geometry.size.width * progress), height: 4)
                }
            }
        }
        .frame(width: 60, height: 4)
    }
}

// MARK: - Receiver Status Card

struct ReceiverStatusCardView: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let card: ReceiverStatusCard
    var isReadOnly: Bool = false
    /// Sends the on-demand request and reports what could be delivered, so the
    /// card never shows "Request sent" when no phone was notified.
    let onCheckOn: () async -> CheckOnOutcome
    /// Returns true when the stand-down succeeded.
    var onStandDown: (() async -> Bool)? = nil
    /// US-IOS016: family the receiver belongs to, so the card can open the
    /// shared care-notes timeline. Nil hides the notes affordance.
    var familyId: UUID? = nil
    /// A caregiver who claimed today's urgent alert ("I've got this").
    var handledBy: String? = nil
    /// Owner only: the receiver's membership row, which opens their schedule
    /// & alerts from the card. Nil hides the link (viewers).
    var settingsMember: FamilyMember? = nil

    /// Transient state for the "Check on" button so a send gives visible and
    /// haptic feedback and the button can't be mashed into duplicates.
    private enum CheckOnState: Equatable { case idle, sending, sent, sentNoDevice }
    @State private var checkOnState: CheckOnState = .idle
    @State private var showStandDownConfirm = false
    @State private var isStandingDown = false

    private var statusColor: Color {
        card.stoodDown && card.status != .needsHelp
            ? .secondary
            : card.status.color(increasedContrast: contrast == .increased)
    }

    /// The receiver still owes an answer (drives the phone-health emphasis).
    private var answerOutstanding: Bool {
        switch card.status {
        case .pending, .missed, .needsHelp: return !card.stoodDown
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if card.status == .needsHelp {
                helpBanner
            }

            header

            // Notification warning (owner-only), only when the server says
            // there's no active device — never on "unknown".
            if !isReadOnly && !card.hasNotificationsEnabled {
                Label("\(card.name) hasn't enabled notifications. They may miss check-in reminders.",
                      systemImage: "bell.slash.fill")
                    .font(.caption)
                    .foregroundStyle(ReceiverCheckInStatus.pending.color(increasedContrast: contrast == .increased))
            }

            if let health = DashboardViewModel.deviceHealth(
                lastSeenAt: card.lastSeenAt,
                batteryLevel: card.batteryLevel,
                answerOutstanding: answerOutstanding
            ) {
                Label(health.text, systemImage: health.isWarning ? "iphone.slash" : "iphone")
                    .font(.caption)
                    .foregroundStyle(health.isWarning
                                     ? ReceiverCheckInStatus.pending.color(increasedContrast: contrast == .increased)
                                     : .secondary)
            }

            // Last check-in — only when it isn't today's (today's time is in
            // the status line), in the receiver's time zone.
            if card.checkedInTime == nil, let lastCheckIn = card.lastCheckIn {
                Label("Last check-in: \(ReceiverTime.formatDateTime(lastCheckIn, timezone: card.timezone))",
                      systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if card.checkedInTime == nil, card.lastCheckIn == nil, card.status != .upcoming {
                Label("No check-ins yet", systemImage: "clock")
                    .font(.caption)
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

            // Kid response type (SOS is already the red banner above).
            if let kidResponse = card.kidResponseType, !kidResponse.isEmpty, card.helpKind != .sos {
                kidResponseBadge(kidResponse)
            }

            escalationSection

            if !card.escalationEnabled && !isReadOnly {
                Label("Escalation is off — you won't be alerted if \(card.name) doesn't answer.",
                      systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isReadOnly {
                checkOnButton
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
                    .frame(minHeight: 44)
                }
                .accessibilityHint("Open the shared care notes for \(card.name).")
            }

            // The card says "Escalation is off" / "Check-ins are paused"; the
            // fix is one tap away instead of on another tab.
            if let settingsMember {
                NavigationLink {
                    ReceiverSettingsView(member: settingsMember)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Schedule & alerts")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44)
                }
                .accessibilityHint("Change \(card.name)'s check-in schedule, pause and alerts.")
            }
        }
        .padding()
        .glassCard(style: .regular, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.name), \(card.status.label). \(card.statusDetail ?? "")")
    }

    // MARK: Pieces

    /// A help request outranks everything on the card: red, first, with the
    /// call one tap away.
    private var helpBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(card.statusDetail ?? card.helpKind?.label ?? "Asked for help",
                  systemImage: "exclamationmark.bubble.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ReceiverCheckInStatus.needsHelp.color(increasedContrast: contrast == .increased))
            if let handledBy {
                Label("\(handledBy) is handling this", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let tel = ContactQuickActions.telURL(card.phone) {
                Link(destination: tel) {
                    Label("Call \(card.name)", systemImage: "phone.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.72, green: 0.0, blue: 0.0))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            // Avatar
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: card.stoodDown && card.status != .needsHelp ? "checkmark.shield" : card.status.icon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Image(systemName: card.status.icon)
                        .font(.caption)
                    Text(card.status.label)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(card.status.color(increasedContrast: contrast == .increased))

                if let detail = card.statusDetail, card.status != .needsHelp {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // US-IOS017: supplementary passive signal — never a substitute
                // for the check-in above, just a calm extra reassurance.
                if card.passiveActiveToday == true {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                        Text("Active today")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Also active today, from Apple Health")
                }
            }

            Spacer()

            // Streak + 7-day consistency chips. Render only when meaningful
            // (StreakChip auto-hides below 2 days; ConsistencyChip auto-hides
            // for the .none tier i.e. <50% consistency). Falls back to the
            // big day-count when neither chip would show.
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
                        .foregroundStyle(DailyOKColor.green600)
                        .contentTransition(.numericText(value: Double(card.streak)))
                        .animation(DailyOKMotion.smoothSpring, value: card.streak)
                    Text("day streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// What the escalation has done and what happens next, in plain words —
    /// for every caregiver. Stand-down is the owner's call.
    @ViewBuilder
    private var escalationSection: some View {
        if card.stoodDown {
            // statusDetail already says "Alerts stopped at …".
            EmptyView()
        } else if card.status == .missed || (card.status != .checkedIn && card.escalationStep >= 1) {
            VStack(alignment: .leading, spacing: 8) {
                Label(escalationText, systemImage: "bell.and.waves.left.and.right.fill")
                    .font(.caption)
                    .foregroundStyle(card.status == .missed
                                     ? ReceiverCheckInStatus.missed.color(increasedContrast: contrast == .increased)
                                     : ReceiverCheckInStatus.pending.color(increasedContrast: contrast == .increased))

                if !isReadOnly, onStandDown != nil {
                    Button {
                        showStandDownConfirm = true
                    } label: {
                        HStack {
                            if isStandingDown {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.shield")
                            }
                            Text(card.status == .missed ? "I've reached them — mark resolved" : "I've reached them — stop alerts")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .disabled(isStandingDown)
                    .accessibilityHint("Stops the escalation reminders and alerts for \(card.name)")
                    .confirmationDialog("Stop alerts for \(card.name)?",
                                        isPresented: $showStandDownConfirm,
                                        titleVisibility: .visible) {
                        Button("Stop alerts", role: .destructive) {
                            DailyOKHaptics.warning()
                            Task { await standDown() }
                        }
                        Button("Keep alerting", role: .cancel) {}
                    } message: {
                        Text("Only do this if you've confirmed \(card.name) is OK. It stops the reminders and caregiver alerts.")
                    }
                }
            }
        }
    }

    private var escalationText: String {
        if card.status == .missed {
            return "\(card.name) didn't answer — all caregivers were alerted."
        }
        let next = card.nextEscalationAt.map { " at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        switch card.escalationStep {
        case 1:
            return "Reminder re-sent to \(card.name). You'll be alerted\(next) if there's still no answer."
        case 2:
            return "You've been alerted. Other caregivers will be alerted\(next) if there's still no answer."
        default:
            return "All caregivers have been alerted. \(card.name) still hasn't answered."
        }
    }

    private func standDown() async {
        guard let onStandDown else { return }
        isStandingDown = true
        let ok = await onStandDown()
        isStandingDown = false
        if ok {
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Alerts stopped for \(card.name)"))
        }
    }

    // MARK: Check on

    private var checkOnButton: some View {
        let alreadyChecked = card.status == .checkedIn
        let quiet = alreadyChecked || card.status == .upcoming
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await checkOn() }
            } label: {
                HStack {
                    switch checkOnState {
                    case .sending:
                        ProgressView()
                        Text("Sending…")
                    case .sent:
                        Image(systemName: "checkmark.circle.fill")
                        Text("Request sent")
                    case .sentNoDevice:
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Not delivered")
                    case .idle:
                        Image(systemName: "bell.badge")
                        Text(alreadyChecked ? "Request another update" : "Check on \(card.name)")
                    }
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            // Deep tints so the white label stays readable (systemOrange /
            // systemGreen fall well under 4.5:1).
            .tint(checkOnTint(quiet: quiet))
            .disabled(checkOnState != .idle)
            .accessibilityLabel(alreadyChecked ? "Request another update from \(card.name)" : "Check on \(card.name)")
            .accessibilityHint("Sends an immediate check-in notification")
            .onDisappear { if checkOnState == .sending { checkOnState = .idle } }

            if checkOnState == .sentNoDevice {
                Text("Saved, but \(card.name)'s phone couldn't be notified. Call instead?")
                    .font(.caption)
                    .foregroundStyle(ReceiverCheckInStatus.pending.color(increasedContrast: contrast == .increased))
            }
        }
    }

    private func checkOnTint(quiet: Bool) -> Color {
        switch checkOnState {
        case .sent: return DailyOKColor.green700
        case .sentNoDevice: return Color(red: 0.62, green: 0.33, blue: 0.0)
        default: return quiet ? Color(red: 0.11, green: 0.36, blue: 0.80) : Color(red: 0.72, green: 0.33, blue: 0.0)
        }
    }

    private func checkOn() async {
        checkOnState = .sending
        let outcome = await onCheckOn()
        switch outcome {
        case .sent(let delivered) where delivered == 0:
            checkOnState = .sentNoDevice
            DailyOKHaptics.warning()
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "Request saved, but \(card.name)'s phone couldn't be notified"))
            try? await Task.sleep(nanoseconds: 8_000_000_000)
        case .sent:
            checkOnState = .sent
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Request sent to \(card.name)"))
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        case .failed:
            // Failure is surfaced by the view model's errorMessage.
            break
        }
        checkOnState = .idle
    }
}

private func locationLabelDisplay(_ rawValue: String) -> String {
    if let label = LocationLabel(rawValue: rawValue) {
        return label.label
    }
    return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
}

private func kidResponseBadge(_ rawValue: String) -> some View {
    // Deep fills so the white label stays readable.
    let config: (text: String, color: Color, icon: String)
    switch rawValue {
    case KidResponseType.pickingMeUp.rawValue:
        config = ("Wants pickup", Color(red: 0.72, green: 0.33, blue: 0.0), "car.fill")
    case KidResponseType.canStayLonger.rawValue:
        config = ("Wants to stay longer", Color(red: 0.11, green: 0.36, blue: 0.80), "clock.fill")
    case KidResponseType.sos.rawValue:
        config = ("SOS!", Color(red: 0.72, green: 0.0, blue: 0.0), "exclamationmark.triangle.fill")
    default:
        config = (rawValue, Color(.darkGray), "bubble.left.fill")
    }

    return HStack(spacing: 4) {
        Image(systemName: config.icon)
            .font(.caption2)
        Text(config.text)
            .font(.caption)
            .fontWeight(.medium)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(config.color, in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Kid response: \(config.text)")
}

// MARK: - Alerts Banner

struct AlertsBannerView: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let alerts: [DailyOKAlert]
    /// For the receiver's name / phone on each alert's Call button.
    var receivers: [ReceiverStatusCard] = []
    var currentUserId: UUID? = nil
    /// Only the owner can clear alerts (RLS); viewers never see the X.
    var isOwner: Bool = true
    let onDismiss: (DailyOKAlert) -> Void
    /// US-IOS013: acknowledge (false) / release (true) so co-caregivers can
    /// coordinate. Optional so existing call sites that don't pass it still work.
    var onAcknowledge: ((DailyOKAlert, Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            ForEach(alerts) { alert in
                alertRow(alert)
            }
        }
    }

    private func accent(for alert: DailyOKAlert) -> Color {
        DashboardViewModel.isUrgent(alert)
            ? ReceiverCheckInStatus.needsHelp.color(increasedContrast: contrast == .increased)
            : ReceiverCheckInStatus.pending.color(increasedContrast: contrast == .increased)
    }

    private func icon(for alert: DailyOKAlert) -> String {
        switch alert.type {
        case "need_help", "sos": return "exclamationmark.bubble.fill"
        case "call_me": return "phone.arrow.down.left.fill"
        case "geofence_breach": return "location.slash.fill"
        case "time_drift": return "clock.badge.exclamationmark"
        case "low_battery": return "battery.25percent"
        case "stale_heartbeat": return "iphone.slash"
        default: return "exclamationmark.triangle.fill"
        }
    }

    /// Urgent alerts can't be cleared until someone has taken them on — a
    /// mis-tap on X used to remove a "Help Requested" for every caregiver.
    private func canDismiss(_ alert: DailyOKAlert) -> Bool {
        isOwner && (!DashboardViewModel.isUrgent(alert) || alert.isAcknowledged)
    }

    @ViewBuilder
    private func alertRow(_ alert: DailyOKAlert) -> some View {
        let urgent = DashboardViewModel.isUrgent(alert)
        let receiver = receivers.first(where: { $0.id == alert.receiverId })
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(for: alert))
                    .font(.title3)
                    .foregroundStyle(accent(for: alert))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(urgent ? .headline : .subheadline.weight(.semibold))
                    Text(alert.message)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.8))
                    // When it happened — a days-old "Help Requested" must not
                    // read as current.
                    Text("\(alert.createdAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.7))

                    if let driftHours = alert.data?["drift_hours"]?.doubleValue {
                        Text("Shifted by \(String(format: "%.1f", driftHours)) hours")
                            .font(.caption2)
                            .foregroundStyle(accent(for: alert))
                    }
                }

                Spacer()

                if canDismiss(alert) {
                    Button {
                        onDismiss(alert)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .frame(minWidth: 44, minHeight: 44) // 44pt tap target (US-IOS112)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss alert")
                }
            }

            if urgent, let tel = ContactQuickActions.telURL(receiver?.phone) {
                Link(destination: tel) {
                    Label("Call \(receiver?.name ?? "them")", systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.72, green: 0.0, blue: 0.0))
            }

            if let onAcknowledge {
                acknowledgementRow(for: alert, onAcknowledge: onAcknowledge)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DailyOKGlass.radiusMedium, style: .continuous)
                .fill(accent(for: alert).opacity(alert.isAcknowledged ? 0.06 : (urgent ? 0.16 : 0.12)))
        )
        .opacity(alert.isAcknowledged ? 0.8 : 1)
    }

    @ViewBuilder
    private func acknowledgementRow(for alert: DailyOKAlert,
                                    onAcknowledge: @escaping (DailyOKAlert, Bool) -> Void) -> some View {
        if alert.isAcknowledged {
            let mine = alert.acknowledgedBy != nil && alert.acknowledgedBy == currentUserId
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(DailyOKColor.green600)
                    .accessibilityHidden(true)
                let who = mine ? String(localized: "you") : (alert.acknowledgedByName ?? String(localized: "a caregiver"))
                let when = alert.acknowledgedAt?.formatted(date: .omitted, time: .shortened) ?? ""
                Text(when.isEmpty ? "Handled by \(who)" : "Handled by \(who) at \(when)")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.8))
                Spacer()
                // Only the caregiver who claimed it (or the owner) can let go
                // of the claim.
                if mine || isOwner {
                    Button("Release") { onAcknowledge(alert, true) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(DailyOKColor.green700)
                        .frame(minHeight: 44)
                        .accessibilityHint("Lets other caregivers know you're no longer handling this.")
                }
            }
        } else {
            Button {
                onAcknowledge(alert, false)
            } label: {
                Label("I've got this", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green700)
            .accessibilityHint("Lets other caregivers know you're handling this so they don't all respond at once.")
        }
    }
}
