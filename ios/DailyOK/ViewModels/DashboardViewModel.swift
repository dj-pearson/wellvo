import SwiftUI
import Supabase

struct ReceiverStatusCard: Identifiable {
    let id: UUID
    let memberId: UUID
    let name: String
    let avatarUrl: String?
    var status: ReceiverCheckInStatus
    var lastCheckIn: Date?
    var streak: Int
    var consistencyPercent: Int = 0
    var mood: Mood?
    var hasNotificationsEnabled: Bool
    var checkedInTime: Date? // Time component only, for timeline
    var locationLabel: String?
    var kidResponseType: String?
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

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeFamilyId: UUID?
    private var realtimeListenerTask: Task<Void, Never>?
    private var pendingRefreshTask: Task<Void, Never>?

    func loadDashboard() async {
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

            var cards: [ReceiverStatusCard] = []
            var weeklyCheckIns: [CheckIn] = []

            for receiver in receivers {
                let receiverTz = receiver.user?.timezone
                let todayCheckIn = try await CheckInService.shared.todayCheckInStatus(
                    receiverId: receiver.userId,
                    familyId: family.id,
                    timezone: receiverTz
                )

                let history = try await CheckInService.shared.checkInHistory(
                    receiverId: receiver.userId,
                    familyId: family.id,
                    days: 30
                )

                let streak = calculateStreak(from: history, timezone: receiverTz)

                // Consistency over the last 7 days, computed from the ISO timestamps
                // of the loaded history. Reuses the shared Streaks utility so the
                // dashboard and receiver-home chips agree.
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let isoTimestamps = history.map { isoFormatter.string(from: $0.checkedInAt) }
                let consistency = Streaks.consistencyPercent(isoTimestamps: isoTimestamps, windowDays: 7)

                // Check notification status — look for active push tokens
                let hasNotifications = await checkNotificationStatus(userId: receiver.userId)

                // Collect last 7 days for weekly summary
                let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                weeklyCheckIns.append(contentsOf: history.filter { $0.checkedInAt >= sevenDaysAgo })

                cards.append(ReceiverStatusCard(
                    id: receiver.userId,
                    memberId: receiver.id,
                    name: receiver.user?.displayName ?? "Unknown",
                    avatarUrl: receiver.user?.avatarUrl,
                    status: todayCheckIn != nil ? .checkedIn : .pending,
                    lastCheckIn: todayCheckIn?.checkedInAt ?? history.first?.checkedInAt,
                    streak: streak,
                    consistencyPercent: consistency,
                    mood: todayCheckIn?.mood,
                    hasNotificationsEnabled: hasNotifications,
                    checkedInTime: todayCheckIn?.checkedInAt,
                    locationLabel: todayCheckIn?.locationLabel,
                    kidResponseType: todayCheckIn?.kidResponseType
                ))
            }

            receiverCards = cards
            weeklySummary = computeWeeklySummary(checkIns: weeklyCheckIns, receiverCount: receivers.count)
            await loadAlerts(familyId: family.id)
            await subscribeToRealtime(familyId: family.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func sendOnDemandCheckIn(to receiverId: UUID) async {
        guard let family else { return }
        do {
            try await CheckInService.shared.sendOnDemandCheckIn(
                receiverId: receiverId,
                familyId: family.id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
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

    // MARK: - Private

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
        var calendar = Calendar.current
        if let tzId = timezone, let tz = TimeZone(identifier: tzId) {
            calendar.timeZone = tz
        }
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

    private func checkNotificationStatus(userId: UUID) async -> Bool {
        do {
            let tokens: [PushTokenRecord] = try await SupabaseService.shared.client
                .from("push_tokens")
                .select("id")
                .eq("user_id", value: userId.uuidString)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value

            return !tokens.isEmpty
        } catch {
            return false // Assume no if can't check
        }
    }

    private func computeWeeklySummary(checkIns: [CheckIn], receiverCount: Int) -> WeeklySummary {
        let totalExpected = receiverCount * 7
        let totalCheckIns = checkIns.count
        let consistency = totalExpected > 0 ? (Double(totalCheckIns) / Double(totalExpected)) * 100 : 0

        // Average check-in time
        let avgTime: String
        if !checkIns.isEmpty {
            let calendar = Calendar.current
            let totalMinutes = checkIns.reduce(0) { sum, checkIn in
                let components = calendar.dateComponents([.hour, .minute], from: checkIn.checkedInAt)
                return sum + (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
            let avgMinutes = totalMinutes / checkIns.count
            let hour = avgMinutes / 60
            let minute = avgMinutes % 60
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            if let date = calendar.date(from: components) {
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
    let id: UUID
}
