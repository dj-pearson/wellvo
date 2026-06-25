import SwiftUI
import Supabase

struct ReceiverStatusCard: Identifiable {
    let id: UUID
    let memberId: UUID
    let name: String
    let avatarUrl: String?
    /// Receiver's phone number (E.164/raw), if known — drives one-tap call /
    /// FaceTime / message quick actions. Nil hides those actions.
    var phone: String?
    var status: ReceiverCheckInStatus
    var lastCheckIn: Date?
    var streak: Int
    var consistencyPercent: Int = 0
    var mood: Mood?
    var hasNotificationsEnabled: Bool
    var checkedInTime: Date? // Time component only, for timeline
    var locationLabel: String?
    var kidResponseType: String?
    /// Current escalation step of an active (pending) request: 0 = none yet,
    /// 1+ = reminders/alerts in progress. Drives the owner "escalating" banner.
    var escalationStep: Int = 0
    /// When the unanswered request was raised (its `created_at`) — i.e. when the
    /// check-in became due. Used as the Live Activity's "overdue since" anchor so
    /// it survives an app restart instead of resetting to now. Nil = not overdue.
    var escalationDueSince: Date? = nil
    /// US-IOS016: number of shared care notes on this receiver, for the card badge.
    var noteCount: Int = 0
    /// US-IOS017: optional passive "active today" signal (Apple Health, opt-in).
    /// Supplements — never replaces — an explicit check-in. Nil = not shared.
    var passiveActiveToday: Bool? = nil
}

enum ReceiverCheckInStatus {
    case checkedIn
    case pending
    case missed
    case noData

    var label: String {
        switch self {
        case .checkedIn: return "Checked In"
        case .pending: return "Pending"
        case .missed: return "Missed"
        case .noData: return "No Data"
        }
    }

    var color: Color {
        switch self {
        case .checkedIn: return .green
        case .pending: return .yellow
        case .missed: return .red
        case .noData: return .gray
        }
    }

    var icon: String {
        switch self {
        case .checkedIn: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .missed: return "exclamationmark.circle.fill"
        case .noData: return "minus.circle.fill"
        }
    }
}

struct WeeklySummary {
    var consistencyPercentage: Double
    var averageCheckInTime: String
    var totalCheckIns: Int
    var totalExpected: Int
    var moodBreakdown: [Mood: Int]
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var family: Family?
    @Published var receiverCards: [ReceiverStatusCard] = []
    @Published var weeklySummary: WeeklySummary?
    @Published var alerts: [DailyOKAlert] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Set true when a milestone (a receiver reaching a multi-day streak) makes
    /// this a good moment to ask for an App Store rating. The view observes this
    /// and presents the system prompt, then resets it.
    @Published var shouldRequestReview = false

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeFamilyId: UUID?
    private var realtimeListenerTask: Task<Void, Never>?
    private var pendingRefreshTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    /// Coalesce the many reload triggers (`.task`, `scenePhase == .active`, tab
    /// switch, realtime, offline-sync, pull-to-refresh). Without this, `.task`
    /// and `scenePhase == .active` both fire on launch and kick off two
    /// concurrent full loads that race on the `@Published` arrays. Re-entrant
    /// callers await the in-flight load instead of starting a new one.
    func loadDashboard() async {
        if let loadTask {
            return await loadTask.value
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        isLoading = true
        errorMessage = nil

        do {
            family = try await FamilyService.shared.getFamily()
            guard let family else {
                isLoading = false
                return
            }

            let members = try await FamilyService.shared.getFamilyMembers(familyId: family.id)
            let receivers = members.filter { $0.role == .receiver && $0.status == .active }

            // Batch notification status into ONE query for all receivers instead
            // of a separate push_tokens SELECT per receiver.
            let notifiedUserIds = await activeNotificationUserIds(userIds: receivers.map(\.userId))

            // Batch each receiver's schedule (one query) so consistency can be
            // judged against the days they were actually scheduled to check in
            // (US-IOS075) — a weekday-only receiver shouldn't be penalized for
            // weekends.
            let settingsByMember = await receiverSettingsByMember(memberIds: receivers.map(\.id))

            var cards: [ReceiverStatusCard] = []
            var weeklyCheckIns: [CheckIn] = []
            // Aggregate a fair, schedule-aware family consistency for the weekly
            // summary instead of assuming 7 expected days per receiver.
            var totalScheduledDays = 0
            var totalCheckedInDays = 0
            // Average check-in time accumulated in each receiver's own timezone.
            var weekMinutesTotal = 0
            var weekMinutesCount = 0

            for receiver in receivers {
                let receiverTz = receiver.user?.timezone

                // Overlap the three independent reads for this receiver instead
                // of awaiting them serially (was ~4 serial round-trips each).
                async let todayCheckInResult = CheckInService.shared.todayCheckInStatus(
                    receiverId: receiver.userId,
                    familyId: family.id,
                    timezone: receiverTz
                )
                async let historyResult = CheckInService.shared.checkInHistory(
                    receiverId: receiver.userId,
                    familyId: family.id,
                    days: 30
                )
                async let activeRequestResult = latestActiveRequest(
                    receiverId: receiver.userId,
                    familyId: family.id
                )

                let todayCheckIn = try await todayCheckInResult
                let history = try await historyResult
                // We must ALWAYS resolve against the latest active (pending/missed)
                // request — not only when there's no check-in today — otherwise an
                // on-demand request sent after a routine morning check-in would be
                // masked by "checked in today" and falsely reassure the owner.
                let activeRequest = await activeRequestResult

                let streak = calculateStreak(from: history, timezone: receiverTz)

                // Consistency over the last 7 days, computed from the ISO timestamps
                // of the loaded history. Reuses the shared Streaks utility so the
                // dashboard and receiver-home chips agree.
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let isoTimestamps = history.map { isoFormatter.string(from: $0.checkedInAt) }
                // Bucket consistency days in the receiver's timezone so the
                // dashboard chip agrees with their "checked in today" status, and
                // only count days they were scheduled to check in (US-IOS075).
                let scheduledWeekdays = settingsByMember[receiver.id]?.scheduledWeekdays
                let consistencyResult = Streaks.scheduleConsistency(
                    isoTimestamps: isoTimestamps,
                    scheduledWeekdays: scheduledWeekdays,
                    windowDays: 7,
                    calendar: .forTimezone(receiverTz)
                )
                let consistency = consistencyResult.percent
                totalScheduledDays += consistencyResult.scheduledDays
                totalCheckedInDays += consistencyResult.checkedInDays

                let hasNotifications = notifiedUserIds.contains(receiver.userId)

                // Collect last 7 days for weekly summary
                let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())
                    ?? Date().addingTimeInterval(-7 * 86_400)
                let recentCheckIns = history.filter { $0.checkedInAt >= sevenDaysAgo }
                weeklyCheckIns.append(contentsOf: recentCheckIns)
                // Accumulate minute-of-day in the receiver's timezone for the
                // family-average check-in time.
                let receiverCal = Calendar.forTimezone(receiverTz)
                for ci in recentCheckIns {
                    let comps = receiverCal.dateComponents([.hour, .minute], from: ci.checkedInAt)
                    weekMinutesTotal += (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                    weekMinutesCount += 1
                }

                let resolved = Self.resolveStatus(todayCheckIn: todayCheckIn, activeRequest: activeRequest)
                let status = resolved.status

                cards.append(ReceiverStatusCard(
                    id: receiver.userId,
                    memberId: receiver.id,
                    name: receiver.user?.displayName ?? "Unknown",
                    avatarUrl: receiver.user?.avatarUrl,
                    phone: receiver.user?.phone,
                    status: status,
                    lastCheckIn: todayCheckIn?.checkedInAt ?? history.first?.checkedInAt,
                    streak: streak,
                    consistencyPercent: consistency,
                    mood: todayCheckIn?.mood,
                    hasNotificationsEnabled: hasNotifications,
                    checkedInTime: todayCheckIn?.checkedInAt,
                    locationLabel: todayCheckIn?.locationLabel,
                    kidResponseType: todayCheckIn?.kidResponseType,
                    escalationStep: resolved.escalationStep,
                    escalationDueSince: resolved.dueSince
                ))
            }

            receiverCards = cards
            // US-IOS016: tally shared care notes per receiver for the card badge.
            await applyNoteCounts(familyId: family.id)
            // US-IOS017: apply any opt-in passive "active today" signals.
            await applyWellnessSignals(familyId: family.id)
            // Mirror status to the App Group so the owner status widget can show
            // an at-a-glance summary without opening the app.
            SharedOwnerPublisher.publish(cards)
            // Start/refresh/end Live Activities for any receiver in escalation.
            EscalationActivityManager.sync(cards: cards, familyId: family.id)
            weeklySummary = computeWeeklySummary(
                checkIns: weeklyCheckIns,
                totalScheduledDays: totalScheduledDays,
                totalCheckedInDays: totalCheckedInDays,
                avgCheckInMinutes: weekMinutesCount > 0 ? weekMinutesTotal / weekMinutesCount : nil
            )
            // A receiver hitting a strong streak is a high-satisfaction moment —
            // flag it so the view can ask for a rating (gated + throttled in the
            // service, so this only fires occasionally and never offline).
            if ReviewPromptService.shared.shouldPromptForOwnerStreak(maxStreak: cards.map(\.streak).max() ?? 0) {
                shouldRequestReview = true
            }
            await loadAlerts(familyId: family.id)
            await subscribeToRealtime(familyId: family.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Returns true when the request was sent, so the card can show an accurate
    /// "Request sent" confirmation (and stay silent on failure, which surfaces
    /// via `errorMessage`).
    @discardableResult
    func sendOnDemandCheckIn(to receiverId: UUID) async -> Bool {
        guard let family else { return false }
        do {
            try await CheckInService.shared.sendOnDemandCheckIn(
                receiverId: receiverId,
                familyId: family.id
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Owner "stand down" — stop the escalation chain for a receiver after
    /// reaching them another way. Optimistically clears the escalating banner.
    func standDownEscalation(for receiverId: UUID) async {
        guard let family else { return }
        do {
            try await CheckInService.shared.cancelEscalation(receiverId: receiverId, familyId: family.id)
            if let idx = receiverCards.firstIndex(where: { $0.id == receiverId }) {
                receiverCards[idx].escalationStep = 0
            }
            // End the Live Activity right away — only after the cancel succeeded,
            // so a failed stand-down does NOT visually clear an active escalation
            // (US-IOS081/US-IOS083).
            EscalationActivityManager.end(receiverId: receiverId.uuidString)
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    /// Latest pending/missed request for a receiver, used to surface escalation
    /// progress on the owner dashboard.
    /// Pure status resolution, extracted so it can be unit-tested.
    ///
    /// Responding to a check-in request marks it `checked_in` server-side, so an
    /// active (pending/missed) request that was created AFTER the most recent
    /// check-in means the receiver has NOT yet responded to *that* request — even
    /// if they did a routine check-in earlier in the day. In that case we surface
    /// the request (and its escalation step) instead of a stale "checked in".
    nonisolated static func resolveStatus(
        todayCheckIn: CheckIn?,
        activeRequest: CheckInRequest?
    ) -> (status: ReceiverCheckInStatus, escalationStep: Int, dueSince: Date?) {
        let unanswered: CheckInRequest?
        if let req = activeRequest,
           !(todayCheckIn.map { $0.checkedInAt >= req.createdAt } ?? false) {
            unanswered = req
        } else {
            unanswered = nil
        }

        let status: ReceiverCheckInStatus
        if let req = unanswered {
            status = req.status == .missed ? .missed : .pending
        } else if todayCheckIn != nil {
            status = .checkedIn
        } else {
            status = .pending
        }
        // `createdAt` is when the request was raised — i.e. when the check-in
        // became due. The Live Activity uses it as the real "overdue since" time.
        return (status, unanswered?.escalationStep ?? 0, unanswered?.createdAt)
    }

    private func latestActiveRequest(receiverId: UUID, familyId: UUID) async -> CheckInRequest? {
        let requests: [CheckInRequest]? = try? await SupabaseService.shared.client
            .from("checkin_requests")
            .select()
            .eq("receiver_id", value: receiverId.uuidString)
            .eq("family_id", value: familyId.uuidString)
            .in("status", values: ["pending", "missed"])
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return requests?.first
    }

    func dismissAlert(_ alert: DailyOKAlert) async {
        do {
            try await SupabaseService.shared.client
                .from("alerts")
                .update(["is_read": true])
                .eq("id", value: alert.id.uuidString)
                .execute()

            alerts.removeAll { $0.id == alert.id }
            await AnalyticsService.shared.track(.alertDismissed, properties: ["type": alert.type])
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    private struct AcknowledgeAlertParams: Encodable {
        let p_alert_id: String
        let p_release: Bool
    }

    /// US-IOS013: acknowledge ("I've got this") or release a family alert via the
    /// `acknowledge_alert` RPC. The resulting UPDATE streams to other caregivers
    /// through the existing `alerts` realtime subscription, so they see
    /// "Handled by <name>" without a manual refresh. The returned row is applied
    /// locally so the tapping caregiver gets instant feedback.
    func acknowledgeAlert(_ alert: DailyOKAlert, release: Bool) async {
        do {
            let updated: DailyOKAlert = try await SupabaseService.shared.client
                .rpc("acknowledge_alert",
                     params: AcknowledgeAlertParams(p_alert_id: alert.id.uuidString, p_release: release))
                .single()
                .execute()
                .value

            if let idx = alerts.firstIndex(where: { $0.id == updated.id }) {
                alerts[idx] = updated
            }
            await AnalyticsService.shared.track(
                release ? .alertReleased : .alertAcknowledged,
                properties: ["type": alert.type]
            )
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    // MARK: - Private

    /// US-IOS016: count care notes per receiver and apply to the cards' badges.
    /// Best-effort — a load failure (or an older backend without the table)
    /// simply leaves every badge at 0.
    private func applyNoteCounts(familyId: UUID) async {
        struct NoteReceiver: Decodable {
            let receiverId: UUID
            enum CodingKeys: String, CodingKey { case receiverId = "receiver_id" }
        }
        do {
            let rows: [NoteReceiver] = try await SupabaseService.shared.client
                .from("care_notes")
                .select("receiver_id")
                .eq("family_id", value: familyId.uuidString)
                .execute()
                .value
            var counts: [UUID: Int] = [:]
            for row in rows { counts[row.receiverId, default: 0] += 1 }
            for i in receiverCards.indices {
                receiverCards[i].noteCount = counts[receiverCards[i].id] ?? 0
            }
        } catch {
            // Non-critical; leave badges at 0.
        }
    }

    /// US-IOS017: mark receivers who have shared a passive "active today" signal
    /// in the last 24h. Best-effort and supplementary — failure leaves it nil.
    private func applyWellnessSignals(familyId: UUID) async {
        struct Signal: Decodable {
            let receiverId: UUID
            let active: Bool
            enum CodingKeys: String, CodingKey { case receiverId = "receiver_id", active }
        }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-24 * 60 * 60))
        do {
            let rows: [Signal] = try await SupabaseService.shared.client
                .from("wellness_signals")
                .select("receiver_id, active")
                .eq("family_id", value: familyId.uuidString)
                .gte("updated_at", value: since)
                .execute()
                .value
            let activeIds = Set(rows.filter { $0.active }.map { $0.receiverId })
            let sharedIds = Set(rows.map { $0.receiverId })
            for i in receiverCards.indices {
                let id = receiverCards[i].id
                receiverCards[i].passiveActiveToday = sharedIds.contains(id) ? activeIds.contains(id) : nil
            }
        } catch {
            // Non-critical; leave as nil.
        }
    }

    private func loadAlerts(familyId: UUID) async {
        do {
            alerts = try await SupabaseService.shared.client
                .from("alerts")
                .select()
                .eq("family_id", value: familyId.uuidString)
                .eq("is_read", value: false)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value
        } catch {
            // Alerts are non-critical, don't surface error
            alerts = []
        }
    }

    private func calculateStreak(from checkIns: [CheckIn], timezone: String? = nil) -> Int {
        guard !checkIns.isEmpty else { return 0 }
        let calendar = Calendar.forTimezone(timezone)
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())

        let checkInDays = Set(checkIns.map { calendar.startOfDay(for: $0.checkedInAt) })

        while checkInDays.contains(currentDate) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
            currentDate = previousDay
        }

        return streak
    }

    /// Which of the given users have at least one active push token — fetched in
    /// a single `in(...)` query rather than one SELECT per receiver.
    private func activeNotificationUserIds(userIds: [UUID]) async -> Set<UUID> {
        guard !userIds.isEmpty else { return [] }
        do {
            let rows: [PushTokenRecord] = try await SupabaseService.shared.client
                .from("push_tokens")
                .select("user_id")
                .in("user_id", values: userIds.map { $0.uuidString })
                .eq("is_active", value: true)
                .execute()
                .value
            return Set(rows.compactMap { UUID(uuidString: $0.user_id) })
        } catch {
            return [] // Assume none if we can't check
        }
    }

    /// Each receiver's settings (keyed by family_member_id) fetched in ONE query,
    /// so consistency can be judged against their real schedule. Falls back to an
    /// empty map (→ "every day expected") if the read fails.
    private func receiverSettingsByMember(memberIds: [UUID]) async -> [UUID: ReceiverSettings] {
        guard !memberIds.isEmpty else { return [:] }
        do {
            let rows: [ReceiverSettings] = try await SupabaseService.shared.client
                .from("receiver_settings")
                .select()
                .in("family_member_id", values: memberIds.map { $0.uuidString })
                .execute()
                .value
            return Dictionary(rows.map { ($0.familyMemberId, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            return [:]
        }
    }

    private func computeWeeklySummary(
        checkIns: [CheckIn],
        totalScheduledDays: Int,
        totalCheckedInDays: Int,
        avgCheckInMinutes: Int?
    ) -> WeeklySummary {
        // Schedule-aware: the denominator is the days receivers were actually
        // scheduled to check in this week (summed across receivers), not a flat
        // receivers × 7. The "X/Y" bubble shows checked-in days / scheduled days.
        let totalExpected = totalScheduledDays
        let totalCheckIns = totalCheckedInDays
        let consistency = totalExpected > 0 ? min(100.0, Double(totalCheckIns) / Double(totalExpected) * 100) : 100

        // Average check-in time — minute-of-day already accumulated in each
        // receiver's own timezone (US-IOS059/075), so the figure isn't skewed by
        // the owner's device zone.
        let avgTime: String
        if let avgMinutes = avgCheckInMinutes {
            let hour = avgMinutes / 60
            let minute = avgMinutes % 60
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            if let date = Calendar.current.date(from: components) {
                avgTime = formatter.string(from: date)
            } else {
                avgTime = "--"
            }
        } else {
            avgTime = "--"
        }

        // Mood breakdown
        var moodBreakdown: [Mood: Int] = [:]
        for checkIn in checkIns {
            if let mood = checkIn.mood {
                moodBreakdown[mood, default: 0] += 1
            }
        }

        return WeeklySummary(
            consistencyPercentage: consistency,
            averageCheckInTime: avgTime,
            totalCheckIns: totalCheckIns,
            totalExpected: totalExpected,
            moodBreakdown: moodBreakdown
        )
    }

    /// Subscribe to realtime changes on the three tables that drive the owner UI:
    ///   - `checkins`          — new "I'm OK" responses flip Pending → Checked In
    ///   - `checkin_requests`  — status transitions (pending → checked_in / missed)
    ///   - `alerts`            — urgent / pattern alerts show in the banner
    ///
    /// The subscription is gated by `family_id` so each owner only receives their
    /// own family's events. Duplicate reloads are debounced (250 ms) so a burst of
    /// events (e.g. edge function inserts a checkin AND updates the request row)
    /// triggers a single refresh.
    private func subscribeToRealtime(familyId: UUID) async {
        // Skip if we're already subscribed to this family
        if realtimeFamilyId == familyId, realtimeChannel != nil {
            return
        }

        // Tear down any prior subscription (family switch, sign-out/sign-in, etc.)
        await teardownRealtime()

        let client = SupabaseService.shared.client
        let channel = client.realtimeV2.channel("owner-dashboard:\(familyId.uuidString)")

        let checkinChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "checkins",
            filter: "family_id=eq.\(familyId.uuidString)"
        )

        let requestChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "checkin_requests",
            filter: "family_id=eq.\(familyId.uuidString)"
        )

        let alertChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "alerts",
            filter: "family_id=eq.\(familyId.uuidString)"
        )

        await channel.subscribe()

        realtimeListenerTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await _ in checkinChanges { await self?.scheduleRefresh() }
                }
                group.addTask { [weak self] in
                    for await _ in requestChanges { await self?.scheduleRefresh() }
                }
                group.addTask { [weak self] in
                    for await _ in alertChanges { await self?.scheduleRefresh() }
                }
            }
        }

        realtimeChannel = channel
        realtimeFamilyId = familyId
    }

    /// Debounced reload — coalesces bursts of realtime events into one reload.
    private func scheduleRefresh() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000) // 250 ms
            guard !Task.isCancelled else { return }
            await self?.loadDashboard()
        }
    }

    private func teardownRealtime() async {
        realtimeListenerTask?.cancel()
        realtimeListenerTask = nil
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        if let channel = realtimeChannel {
            await channel.unsubscribe()
        }
        realtimeChannel = nil
        realtimeFamilyId = nil
    }
}

/// Minimal struct to decode push_token existence check
private struct PushTokenRecord: Codable {
    let user_id: String
}
