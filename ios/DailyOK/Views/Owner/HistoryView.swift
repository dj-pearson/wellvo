import SwiftUI

/// History for one receiver: summary, calendar, first-check-in trend and a
/// per-day log, plus a PDF report. Shared by owners and viewers.
///
/// Every section reads the same `HistoryDay` model (HistoryTimeline), built
/// from the receiver's check-ins AND check-in requests, so a day the dashboard
/// showed as Needs Help, Missed or "Alerts stopped" reads the same here and in
/// the exported report.
struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    // Family / picker
    @State private var family: Family?
    @State private var members: [FamilyMember] = []
    /// Receivers who haven't accepted their invite yet — named in the empty
    /// state instead of a generic "no history".
    @State private var invitedReceivers: [FamilyMember] = []
    @State private var membersLoaded = false
    @State private var membersError = false
    @State private var selectedReceiver: FamilyMember?
    @State private var selectedDays = 30

    // Loaded data — always belongs to `loadedKey`, never to whatever happens
    // to be selected while a request is in flight.
    @State private var loadedKey: HistoryLoadKey?
    /// Everything fetched (at least 31 days, so the dashboard's 30-day streak
    /// lookback is always covered); the window's days are in `historyDays`.
    @State private var checkIns: [CheckIn] = []
    @State private var historyDays: [HistoryDay] = []
    @State private var receiverSettings: ReceiverSettings?
    @State private var requestsAvailable = true
    @State private var lastLoadedAt: Date?

    /// Skeleton: nothing to show for the selected receiver yet.
    @State private var isLoading = false
    /// Background refresh with data already on screen (stale-while-revalidate).
    @State private var isRefreshing = false
    /// Set when the history fetch fails with nothing on screen, so a network
    /// error renders "couldn't load" + Retry instead of an empty history.
    @State private var loadError = false
    /// A refresh failed; the earlier history stays on screen with a strip.
    @State private var refreshFailed = false
    /// Bumped by every load; a load whose number is stale drops its result, so
    /// a slow response can't land under a different receiver's name.
    @State private var loadGeneration = 0
    @State private var loadTask: Task<Void, Never>?

    @State private var selectedDay: HistoryDay?
    @State private var sharedReport: SharedReport?
    @State private var isExporting = false
    @State private var exportError: String?

    private var receiverTz: String? { selectedReceiver?.user?.timezone }
    private var receiverName: String { selectedReceiver?.user?.displayName ?? "Unknown" }
    private var isViewer: Bool { appState.currentUserRole == .viewer }

    /// Data on screen belongs to the selected receiver and period.
    private var showsCurrentSelection: Bool {
        guard let loadedKey, let selectedReceiver else { return false }
        return loadedKey.memberId == selectedReceiver.id && loadedKey.days == selectedDays
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $selectedDays) {
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .accessibilityLabel("History time period")

                    receiverPicker

                    content
                }
                .padding(.bottom)
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: .neutral))
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isRefreshing && !isLoading {
                        ProgressView()
                            .accessibilityLabel("Updating history")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await exportPDF() }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(!showsCurrentSelection || isExporting)
                    .accessibilityLabel(isExporting ? "Generating report" : "Export report for \(receiverName)")
                }
            }
            .alert("Export Failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .refreshable {
                reload(members: true)
                await loadTask?.value
            }
            .task { reload(members: true) }
            .onChange(of: selectedDays) { _ in
                reload(members: false)
            }
            // SwiftUI keeps tabs alive, so `.task` only fires once. Reload when
            // the History tab is shown or the app comes back while it's on
            // screen — not on every foreground while another tab is up.
            .onChange(of: appState.selectedTab) { newTab in
                if newTab == .history { reload(members: true) }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active && appState.selectedTab == .history {
                    reload(members: true)
                }
            }
            .sheet(item: $selectedDay) { day in
                HistoryDayDetailView(day: day, receiverName: receiverName, timezone: receiverTz)
            }
            .sheet(item: $sharedReport) { report in
                ShareSheet(activityItems: [report.url])
                    .dailyokGlassSheet(style: .regular)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var receiverPicker: some View {
        if members.count > 1 || (members.count == 1 && selectedReceiver == nil) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(members) { member in
                        let isSelected = selectedReceiver?.id == member.id
                        Button {
                            guard !isSelected else { return }
                            selectedReceiver = member
                            reload(members: false)
                        } label: {
                            Text(member.user?.displayName ?? "Unknown")
                                .font(.subheadline)
                                .fontWeight(isSelected ? .bold : .regular)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44) // comfortable tap target
                                .background(
                                    Capsule().fill(isSelected ? AnyShapeStyle(DailyOKColor.green700) : AnyShapeStyle(.thinMaterial))
                                )
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("View history for \(member.user?.displayName ?? "Unknown")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
            }
        } else if let selectedReceiver {
            Text(selectedReceiver.user?.displayName ?? "Unknown")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !membersLoaded {
            HistorySkeletonView()
        } else if members.isEmpty {
            if membersError {
                EmptyStateView(
                    systemImage: "wifi.exclamationmark",
                    title: "Couldn't load your family",
                    message: "We couldn't reach the server. Check your connection and try again.",
                    primaryActionLabel: "Try Again",
                    onPrimaryAction: { reload(members: true) }
                )
                .padding(.top, 20)
            } else {
                noReceiversState
                    .padding(.top, 20)
            }
        } else if isLoading || (loadedKey == nil && !loadError) {
            HistorySkeletonView()
        } else if loadError {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "Couldn't load history",
                message: "We couldn't reach the server. Check your connection and try again.",
                primaryActionLabel: "Retry",
                onPrimaryAction: { reload(members: false) }
            )
            .padding(.top, 20)
        } else {
            loadedContent
        }
    }

    @ViewBuilder
    private var noReceiversState: some View {
        if let invited = invitedReceivers.first {
            EmptyStateView(
                systemImage: "hourglass",
                title: "Waiting for \(invited.user?.displayName ?? "them") to join",
                message: "Their check-in history starts once they accept the invite."
            )
        } else if isViewer {
            EmptyStateView(
                systemImage: "person.2",
                title: "No one to show yet",
                message: "When the family owner adds someone to check on, their history shows up here."
            )
        } else {
            EmptyStateView(
                systemImage: "person.badge.plus",
                title: "No one to show yet",
                message: "Add the person you check on from the Family tab. Their history shows up here.",
                primaryActionLabel: "Go to Family",
                onPrimaryAction: { appState.selectedTab = .family }
            )
        }
    }

    private var loadedContent: some View {
        let stats = HistoryTimeline.stats(for: historyDays)
        return VStack(spacing: 16) {
            if refreshFailed {
                StaleDataStrip(
                    lastUpdatedAt: lastLoadedAt,
                    detail: "History couldn't be refreshed. The days shown may be out of date.",
                    isLoading: isRefreshing,
                    onRetry: { reload(members: false) }
                )
                .padding(.horizontal)
            }

            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            summaryCard(stats)
                .padding(.horizontal)

            CalendarHeatmapView(
                days: historyDays,
                timezone: receiverTz,
                accessibilitySummary: heatmapSummary(stats),
                onSelect: { selectedDay = $0 }
            )
            .padding(.horizontal)

            CheckInTrendChartView(
                checkIns: checkIns,
                days: loadedKey?.days ?? selectedDays,
                timezone: receiverTz
            )
            .padding(.horizontal)

            logCard
                .padding(.horizontal)
        }
    }

    /// One-line explanations of how to read the screen, only when needed.
    private var notes: [String] {
        var notes: [String] = []
        if let id = receiverTz, let tz = TimeZone(identifier: id),
           tz.secondsFromGMT() != TimeZone.current.secondsFromGMT() {
            notes.append("Times are in \(receiverName)'s time (\(tz.abbreviation() ?? id)).")
        }
        if !requestsAvailable {
            notes.append(receiverSettings == nil
                ? "Couldn't load the schedule, so days without a check-in aren't marked missed."
                : "Couldn't load check-in requests, so missed days are estimated from the current schedule.")
        }
        return notes
    }

    private func summaryCard(_ stats: HistoryStats) -> some View {
        let days = loadedKey?.days ?? selectedDays
        let streak = HistoryTimeline.currentStreak(
            checkIns: checkIns, now: lastLoadedAt ?? Date(), calendar: Calendar.forTimezone(receiverTz)
        )
        let counts = [
            SummaryCount(label: "Missed", value: stats.missedDays, color: ReceiverCheckInStatus.missed.color),
            SummaryCount(label: "Reached another way", value: stats.stoodDownDays, color: .secondary),
            SummaryCount(label: "After an alert", value: stats.lateDays, color: ReceiverCheckInStatus.pending.color),
            SummaryCount(label: "Asked for help", value: stats.helpRequests, color: ReceiverCheckInStatus.needsHelp.color),
        ].filter { $0.value > 0 }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Last \(days) days")
                .font(.headline)

            if let percent = stats.percent {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(percent)%")
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text("checked in on \(stats.answeredDays) of \(stats.expectedDays) days a check-in was due")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No check-ins were due in this period.")
                    .font(.subheadline)
            }

            if counts.isEmpty {
                if stats.expectedDays > 0 {
                    Text("No missed days and no help requests.")
                        .font(.subheadline)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(counts) { count in
                        HStack(spacing: 6) {
                            Circle().fill(count.color).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text("\(count.label): \(count.value)")
                                .font(.subheadline)
                        }
                    }
                }
            }

            Text("Current streak: \(streak) day\(streak == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level2)
    }

    private func heatmapSummary(_ stats: HistoryStats) -> String {
        let days = loadedKey?.days ?? selectedDays
        guard stats.expectedDays > 0 else { return "Last \(days) days: no check-ins were due." }
        var parts = ["\(stats.answeredDays) of \(stats.expectedDays) days checked in"]
        if stats.lateDays > 0 { parts.append("\(stats.lateDays) after an alert") }
        if stats.missedDays > 0 { parts.append("\(stats.missedDays) missed") }
        if stats.stoodDownDays > 0 { parts.append("\(stats.stoodDownDays) reached another way") }
        if stats.helpRequests > 0 { parts.append("\(stats.helpRequests) help request\(stats.helpRequests == 1 ? "" : "s")") }
        return "Last \(days) days: " + parts.joined(separator: ", ") + "."
    }

    private var logCard: some View {
        let loggedDays = historyDays.reversed().filter { !$0.events.isEmpty }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Check-In Log")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if loggedDays.isEmpty {
                Text(emptyLogMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(loggedDays) { day in
                        Button {
                            selectedDay = day
                        } label: {
                            HistoryDaySection(day: day, timezone: receiverTz)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level2)
    }

    private var emptyLogMessage: String {
        let days = loadedKey?.days ?? selectedDays
        let calendar = Calendar.forTimezone(receiverTz)
        if let joined = selectedReceiver?.joinedAt,
           let first = historyDays.first, calendar.startOfDay(for: joined) > first.date {
            return "\(receiverName) joined on \(HistoryDaySection.dayTitle(joined, timezone: receiverTz)). Their first check-in will appear here."
        }
        return "Nothing was asked or answered in the last \(days) days."
    }

    // MARK: - Loading

    /// Start a load, cancelling the one in flight. Every entry point goes
    /// through here so two loads never race to fill the screen.
    private func reload(members reloadMembers: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            if reloadMembers {
                await loadMembers()
            } else {
                await loadHistory()
            }
        }
    }

    private func loadMembers() async {
        do {
            guard let fetchedFamily = try await FamilyService.shared.getFamily() else {
                guard !Task.isCancelled else { return }
                family = nil
                members = []
                invitedReceivers = []
                selectedReceiver = nil
                membersError = false
                membersLoaded = true
                clearHistory()
                return
            }
            let all = try await FamilyService.shared.getFamilyMembers(familyId: fetchedFamily.id)
            guard !Task.isCancelled else { return }
            family = fetchedFamily
            members = all.filter { $0.role == .receiver && $0.status == .active }
            invitedReceivers = all.filter { $0.role == .receiver && $0.status == .invited }
            membersError = false
            membersLoaded = true
            // Re-resolve the selection against the freshly-fetched list: keep it
            // if that receiver still exists (refreshing to the new instance),
            // otherwise fall back to the first. A receiver removed from the
            // family must not stay "selected" over their stale history.
            if let current = selectedReceiver, let stillPresent = members.first(where: { $0.id == current.id }) {
                selectedReceiver = stillPresent
            } else {
                selectedReceiver = members.first
            }
        } catch {
            guard !Task.isCancelled else { return }
            // Keep whatever is on screen; with nothing on screen the
            // "Couldn't load your family" state shows. Never the false
            // "no history" empty state.
            Log.general.error("History: failed to load family members: \(error.localizedDescription, privacy: .public)")
            membersError = true
            membersLoaded = true
            if members.isEmpty { return }
        }
        await loadHistory()
    }

    private func loadHistory() async {
        guard let receiver = selectedReceiver else {
            clearHistory()
            return
        }
        let key = HistoryLoadKey(memberId: receiver.id, days: selectedDays)
        loadGeneration += 1
        let generation = loadGeneration

        if loadedKey?.memberId != receiver.id {
            // Never show the previous receiver's data under this name (US-IOS111).
            clearHistory()
            isLoading = true
        } else {
            isRefreshing = true
        }
        loadError = false

        let calendar = Calendar.forTimezone(receiver.user?.timezone)
        let now = Date()
        let window = HistoryTimeline.window(days: key.days, now: now, calendar: calendar)
        // At least 31 days of check-ins so the streak matches the dashboard's,
        // bounded above by the end of today so future-dated rows aren't read.
        let fetchDays = max(key.days, 31)
        let fetchStart = HistoryTimeline.window(days: fetchDays, now: now, calendar: calendar).start

        do {
            guard let familyId = try await resolvedFamilyId() else { throw HistoryLoadError.noFamily }
            async let checkInsTask = CheckInService.shared.checkInHistory(
                receiverId: receiver.userId,
                familyId: familyId,
                from: fetchStart,
                to: window.end,
                limit: fetchDays * 12
            )
            async let requestsTask = CheckInService.shared.checkInRequestHistory(
                receiverId: receiver.userId,
                familyId: familyId,
                from: window.start,
                to: window.end
            )
            async let settingsTask = CheckInService.shared.receiverSchedule(
                familyMemberId: receiver.id,
                familyId: familyId
            )
            let fetched = try await checkInsTask
            // Requests and schedule degrade gracefully: without them the
            // days are estimated (and say so), never failed outright.
            let requests = try? await requestsTask
            let settings = await settingsTask

            // A newer load (another receiver, period, or refresh) owns the
            // screen now — drop this result.
            guard generation == loadGeneration, !Task.isCancelled else { return }

            historyDays = HistoryTimeline.build(
                checkIns: fetched,
                requests: requests,
                settings: settings,
                enrolledSince: receiver.joinedAt ?? receiver.invitedAt,
                days: key.days,
                now: now,
                calendar: calendar
            )
            checkIns = fetched
            receiverSettings = settings
            requestsAvailable = requests != nil
            loadedKey = key
            lastLoadedAt = now
            refreshFailed = false
        } catch {
            // Cancelled or superseded: the load that replaced this one owns
            // the loading flags and the error state.
            guard generation == loadGeneration, !Task.isCancelled else { return }
            Log.general.error("Failed to load check-in history: \(error.localizedDescription, privacy: .public)")
            if loadedKey?.memberId == receiver.id {
                // Keep the history that's on screen; say it may be stale.
                refreshFailed = true
            } else {
                loadError = true
            }
        }
        isLoading = false
        isRefreshing = false
    }

    private func resolvedFamilyId() async throws -> UUID? {
        if let family { return family.id }
        let fetched = try await FamilyService.shared.getFamily()
        family = fetched
        return fetched?.id
    }

    private func clearHistory() {
        loadedKey = nil
        checkIns = []
        historyDays = []
        receiverSettings = nil
        requestsAvailable = true
        refreshFailed = false
        loadError = false
        isLoading = false
        isRefreshing = false
    }

    // MARK: - Export

    private func exportPDF() async {
        guard !isExporting, showsCurrentSelection, let receiver = selectedReceiver, let key = loadedKey else { return }
        isExporting = true
        defer { isExporting = false }

        // Snapshot everything BEFORE any await: switching receivers mid-export
        // must not pair one person's name with another's check-ins.
        let days = historyDays
        let allCheckIns = checkIns
        let timezone = receiver.user?.timezone
        let name = receiver.user?.displayName ?? "Unknown"
        let loadedAt = lastLoadedAt
        var familyName = family?.name
        if familyName == nil {
            familyName = try? await FamilyService.shared.getFamily()?.name
        }

        // The report describes the loaded snapshot: its days were judged at
        // load time, so the period, streak and file name use that moment too —
        // exporting after midnight must not shift the period by a day while
        // the days (and the screen) still show the loaded window.
        let now = loadedAt ?? Date()
        let calendar = Calendar.forTimezone(timezone)
        let reportData = CheckInReportGenerator.ReportData(
            receiverName: name,
            familyName: familyName ?? "Daily OK",
            checkIns: allCheckIns,
            periodDays: key.days,
            generatedAt: now,
            timezone: timezone,
            days: days,
            streak: HistoryTimeline.currentStreak(checkIns: allCheckIns, now: now, calendar: calendar)
        )

        // Generate off the main actor so a large (e.g. 90-day) report can't
        // freeze the UI while the spinner shows. ReportData is Sendable.
        let data = await Task.detached(priority: .userInitiated) {
            CheckInReportGenerator.generatePDF(from: reportData)
        }.value

        // Don't present an empty share sheet — surface an error instead.
        guard !data.isEmpty else {
            exportError = "Couldn't generate the report. Please try again."
            return
        }

        // Share a named file, not anonymous Data, so Mail and Files show
        // "Daily OK – Mom – Aug 29–Sep 27.pdf".
        let window = HistoryTimeline.window(days: key.days, now: now, calendar: calendar)
        let fileName = CheckInReportGenerator.fileName(receiverName: name, start: window.start, end: now, calendar: calendar)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            sharedReport = SharedReport(url: url)
        } catch {
            Log.general.error("History: couldn't write report: \(error.localizedDescription, privacy: .public)")
            exportError = "Couldn't save the report. Please try again."
        }
    }
}

private struct HistoryLoadKey: Equatable {
    let memberId: UUID
    let days: Int
}

private enum HistoryLoadError: Error {
    case noFamily
}

private struct SummaryCount: Identifiable {
    let label: String
    let value: Int
    let color: Color
    var id: String { label }
}

private struct SharedReport: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Log rows

/// One day in the log: its date and state, then what happened, in order.
private struct HistoryDaySection: View {
    let day: HistoryDay
    let timezone: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.dayTitle(day.date, timezone: timezone))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(
                    HistoryTimeline.label(for: day.status, help: day.helpKind, timezone: timezone),
                    systemImage: HistoryStyle.icon(for: day.status)
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(HistoryStyle.color(for: day.status))
            }
            ForEach(day.events) { event in
                HistoryEventRow(event: event, timezone: timezone)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows this day's details")
    }

    /// "Tue, Sep 22" in the receiver's calendar.
    static func dayTitle(_ date: Date, timezone: String?) -> String {
        let calendar = Calendar.forTimezone(timezone)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: date)
    }
}

private struct HistoryEventRow: View {
    let event: HistoryEvent
    let timezone: String?

    var body: some View {
        let time = ReceiverTime.format(event.at, timezone: timezone)
        let title = HistoryTimeline.title(for: event)
        let detail = HistoryTimeline.detail(for: event)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: HistoryStyle.icon(for: event))
                .foregroundStyle(HistoryStyle.color(for: event))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(time)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(time): \(title)\(detail.map { ". \($0)" } ?? "")")
    }
}

/// Icons and colors shared by the log and the day detail — the dashboard's
/// status colors, so "missed" and "needs help" look the same on both tabs.
private enum HistoryStyle {
    static func icon(for status: HistoryDayStatus) -> String {
        switch status {
        case .onTime: return "checkmark.circle.fill"
        case .late: return "clock.badge.exclamationmark.fill"
        case .missed: return "xmark.circle.fill"
        case .stoodDown: return "hand.raised.fill"
        case .needsHelp: return "exclamationmark.bubble.fill"
        case .waiting: return "clock.fill"
        case .dueLater: return "calendar.badge.clock"
        case .notAsked: return "minus.circle"
        }
    }

    static func color(for status: HistoryDayStatus) -> Color {
        switch status {
        case .onTime: return ReceiverCheckInStatus.checkedIn.color
        case .late, .waiting: return ReceiverCheckInStatus.pending.color
        case .missed: return ReceiverCheckInStatus.missed.color
        case .needsHelp: return ReceiverCheckInStatus.needsHelp.color
        case .stoodDown, .dueLater, .notAsked: return .secondary
        }
    }

    static func icon(for event: HistoryEvent) -> String {
        switch event.kind {
        case .checkIn(_, let help, let afterAlert):
            if help != nil { return "exclamationmark.bubble.fill" }
            return afterAlert ? "clock.badge.exclamationmark.fill" : "checkmark.circle.fill"
        case .unanswered(_, _, let live):
            return live ? "clock.fill" : "xmark.circle.fill"
        case .stoodDown:
            return "hand.raised.fill"
        }
    }

    static func color(for event: HistoryEvent) -> Color {
        switch event.kind {
        case .checkIn(_, let help, let afterAlert):
            if help != nil { return ReceiverCheckInStatus.needsHelp.color }
            return afterAlert ? ReceiverCheckInStatus.pending.color : ReceiverCheckInStatus.checkedIn.color
        case .unanswered(_, _, let live):
            return live ? ReceiverCheckInStatus.pending.color : ReceiverCheckInStatus.missed.color
        case .stoodDown:
            return .secondary
        }
    }
}

// MARK: - Day detail

/// What happened on one day — opened from the calendar or the log.
private struct HistoryDayDetailView: View {
    let day: HistoryDay
    let receiverName: String
    let timezone: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        HistoryTimeline.label(for: day.status, help: day.helpKind, timezone: timezone),
                        systemImage: HistoryStyle.icon(for: day.status)
                    )
                    .foregroundStyle(HistoryStyle.color(for: day.status))
                    .font(.headline)
                    if let explanation {
                        Text(explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("What happened") {
                    if day.events.isEmpty {
                        Text("Nothing was asked or answered this day.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(day.events) { event in
                            HistoryEventRow(event: event, timezone: timezone)
                        }
                    }
                }
            }
            .navigationTitle(HistoryDaySection.dayTitle(day.date, timezone: timezone))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var explanation: String? {
        switch day.status {
        case .late: return "\(receiverName) checked in, but only after the family had been alerted."
        case .missed: return "A check-in was asked for and \(receiverName) didn't answer that day."
        case .stoodDown: return "\(receiverName) didn't answer, and a caregiver stopped the alerts after reaching them another way."
        case .needsHelp: return "\(receiverName) asked for help this day."
        case .notAsked: return "No check-in was asked for — an off day, a paused schedule, or before \(receiverName) joined."
        case .dueLater: return "Today's check-in isn't due yet."
        case .waiting: return "\(receiverName) was asked and hasn't answered yet."
        case .onTime: return nil
        }
    }
}

// MARK: - UIKit ShareSheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
