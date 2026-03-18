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
    var mood: Mood?
    var hasNotificationsEnabled: Bool
    var checkedInTime: Date? // Time component only, for timeline
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
    @Published var alerts: [WellvoAlert] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var realtimeChannel: RealtimeChannelV2?

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
                let todayCheckIn = try await CheckInService.shared.todayCheckInStatus(
                    receiverId: receiver.userId,
                    familyId: family.id
                )

                let history = try await CheckInService.shared.checkInHistory(
                    receiverId: receiver.userId,
                    familyId: family.id,
                    days: 30
                )

                let streak = calculateStreak(from: history)

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
                    mood: todayCheckIn?.mood,
                    hasNotificationsEnabled: hasNotifications,
                    checkedInTime: todayCheckIn?.checkedInAt
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

    func dismissAlert(_ alert: WellvoAlert) async {
        do {
            try await SupabaseService.shared.client
                .from("alerts")
                .update(["is_read": true])
                .eq("id", value: alert.id.uuidString)
                .execute()

            alerts.removeAll { $0.id == alert.id }
            await AnalyticsService.shared.track(.alertDismissed, properties: ["type": alert.type])
        } catch {
            print("Failed to dismiss alert: \(error)")
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

    private func calculateStreak(from checkIns: [CheckIn]) -> Int {
        guard !checkIns.isEmpty else { return 0 }
        let calendar = Calendar.current
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

    private func subscribeToRealtime(familyId: UUID) async {
        let channel = SupabaseService.shared.client.realtimeV2.channel("checkins:\(familyId.uuidString)")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "checkins",
            filter: "family_id=eq.\(familyId.uuidString)"
        )

        await channel.subscribe()

        Task {
            for await _ in changes {
                await loadDashboard()
            }
        }

        realtimeChannel = channel
    }
}

/// Minimal struct to decode push_token existence check
private struct PushTokenRecord: Codable {
    let id: UUID
}
