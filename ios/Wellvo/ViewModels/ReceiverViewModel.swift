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
    }

    func performCheckIn(mood: Mood? = nil) async {
        guard let familyId, !isCheckingIn else { return }

        isCheckingIn = true
        errorMessage = nil

        do {
            let checkIn = try await CheckInService.shared.checkIn(
                familyId: familyId,
                mood: mood,
                source: .app
            )
            lastCheckIn = checkIn
            hasCheckedInToday = true

            if mood == nil {
                showMoodSelector = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isCheckingIn = false
    }

    func submitMood(_ mood: Mood) async {
        selectedMood = mood
        showMoodSelector = false
        // Mood is sent with the next check-in or updated on the current one
    }
}
