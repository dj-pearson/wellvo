import SwiftUI
import Supabase

@MainActor
final class ReceiverViewModel: ObservableObject {
    @Published var hasCheckedInToday = false
    @Published var isCheckingIn = false
    @Published var showMoodSelector = false
    @Published var selectedMood: Mood?
    @Published var lastCheckIn: CheckIn?
    @Published var errorMessage: String?
    @Published var familyId: UUID?
    @Published var isOffline = false
    @Published var pendingOfflineCount = 0
    @Published var receiverMode: ReceiverMode = .standard
    @Published var selectedLocationLabel: LocationLabel?
    @Published var selectedKidResponse: KidResponseType?
    @Published var nextCheckInTime: Date?
    @Published var receiverSettings: ReceiverSettings?

    private let offlineService = OfflineCheckInService.shared

    func loadStatus() async {
        guard let family = try? await FamilyService.shared.getFamily() else { return }
        familyId = family.id

        guard let session = try? await SupabaseService.shared.client.auth.session else { return }

        if let todayCheckIn = try? await CheckInService.shared.todayCheckInStatus(
            receiverId: session.user.id,
            familyId: family.id
        ) {
            lastCheckIn = todayCheckIn
            hasCheckedInToday = true
        }

        // Fetch receiver settings to determine receiver mode
        await loadReceiverSettings(userId: session.user.id, familyId: family.id)

        // Sync any pending offline check-ins
        await offlineService.syncPendingCheckIns()
        isOffline = !offlineService.isOnline
        pendingOfflineCount = offlineService.pendingCount
    }

    private func loadReceiverSettings(userId: UUID, familyId: UUID) async {
        do {
            // Find the family member record for this user
            let members: [FamilyMember] = try await SupabaseService.shared.client
                .from("family_members")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("family_id", value: familyId.uuidString)
                .limit(1)
                .execute()
                .value

            guard let member = members.first else { return }

            // Fetch receiver_settings by family_member_id
            let settings: ReceiverSettings = try await SupabaseService.shared.client
                .from("receiver_settings")
                .select()
                .eq("family_member_id", value: member.id.uuidString)
                .single()
                .execute()
                .value

            receiverSettings = settings
            receiverMode = settings.receiverMode
            computeNextCheckInTime(from: settings)
        } catch {
            // Non-critical — default to standard mode
        }
    }

    private func computeNextCheckInTime(from settings: ReceiverSettings) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        // checkinTime may come as "HH:mm" or "HH:mm:ss"
        let timeString = String(settings.checkinTime.prefix(5))
        guard let parsedTime = formatter.date(from: timeString) else { return }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: parsedTime)
        var tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        tomorrow = calendar.date(bySettingHour: timeComponents.hour ?? 9,
                                  minute: timeComponents.minute ?? 0,
                                  second: 0,
                                  of: tomorrow) ?? tomorrow
        nextCheckInTime = tomorrow
    }

    func performCheckIn(mood: Mood? = nil) async {
        guard let familyId, !isCheckingIn else { return }

        isCheckingIn = true
        errorMessage = nil

        do {
            let checkIn = try await offlineService.performCheckIn(
                familyId: familyId,
                mood: mood,
                source: .app
            )

            if let checkIn {
                lastCheckIn = checkIn
            }
            hasCheckedInToday = true
            Task { await AnalyticsService.shared.track(.checkIn) }

            if mood == nil {
                showMoodSelector = true
            }
        } catch let error as NetworkError {
            // Offline — check-in was queued
            hasCheckedInToday = true
            isOffline = true
            Task { await AnalyticsService.shared.track(.checkInOffline) }
            pendingOfflineCount = offlineService.pendingCount
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isCheckingIn = false
    }

    func submitMood(_ mood: Mood) async {
        selectedMood = mood
        showMoodSelector = false
        Task { await AnalyticsService.shared.track(.moodSubmitted, properties: ["mood": mood.rawValue]) }
    }

    func submitLocationLabel(_ label: LocationLabel) {
        selectedLocationLabel = label
        Task { await AnalyticsService.shared.track(.checkIn, properties: ["location_label": label.rawValue]) }
    }

    func submitKidResponse(_ type: KidResponseType) async {
        selectedKidResponse = type
        guard let familyId else { return }

        do {
            _ = try await CheckInService.shared.checkIn(
                familyId: familyId,
                source: .app,
                kidResponseType: type.rawValue
            )
            Task { await AnalyticsService.shared.track(.checkIn, properties: ["kid_response": type.rawValue]) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
