import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case userType
    case createFamily
    case choosePlan
    case addReceiver
    case notifications
    case complete
}

enum UserTypeSelection: String {
    case agingParent = "aging_parent"
    case teenager = "teenager"
    case other = "other"
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var userTypeSelection: UserTypeSelection?
    @Published var familyName = ""
    @Published var receiverName = ""
    @Published var receiverPhone = ""
    @Published var checkinTime = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?

    var createdFamily: Family?

    func advance() {
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation { currentStep = nextStep }
    }

    func goBack() {
        guard let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation { currentStep = prevStep }
    }

    func createFamily() async {
        guard !familyName.isEmpty else {
            errorMessage = "Please enter a family name"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            createdFamily = try await FamilyService.shared.createFamily(name: familyName)
            advance()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func inviteReceiver() async {
        guard let family = createdFamily,
              !receiverName.isEmpty,
              !receiverPhone.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }

        isLoading = true
        errorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: checkinTime)

        do {
            try await FamilyService.shared.inviteReceiver(
                familyId: family.id,
                name: receiverName,
                phone: receiverPhone,
                checkinTime: timeString
            )
            advance()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func requestNotificationPermission() async {
        let granted = await PushNotificationService.shared.requestPermission()
        if granted {
            advance()
        } else {
            errorMessage = "Notifications are important for Wellvo to work. You can enable them in Settings."
            advance() // Still proceed, but show the warning
        }
    }
}
