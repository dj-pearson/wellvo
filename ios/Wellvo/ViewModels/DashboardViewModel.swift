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

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var family: Family?
    @Published var receiverCards: [ReceiverStatusCard] = []
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

                cards.append(ReceiverStatusCard(
                    id: receiver.userId,
                    memberId: receiver.id,
                    name: receiver.user?.displayName ?? "Unknown",
                    avatarUrl: receiver.user?.avatarUrl,
                    status: todayCheckIn != nil ? .checkedIn : .pending,
                    lastCheckIn: todayCheckIn?.checkedInAt ?? history.first?.checkedInAt,
                    streak: streak,
                    mood: todayCheckIn?.mood
                ))
            }

            receiverCards = cards
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

    // MARK: - Private

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
