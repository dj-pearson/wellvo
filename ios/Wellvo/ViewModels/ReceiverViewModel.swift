import SwiftUI

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

        // Sync any pending offline check-ins
        await offlineService.syncPendingCheckIns()
        isOffline = !offlineService.isOnline
        pendingOfflineCount = offlineService.pendingCount
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
}
