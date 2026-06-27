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
    /// True once the user has been asked for notification permission and denied it.
    /// Drives the inline recovery UI (Open Settings / Continue anyway) instead of
    /// silently walking the user into the "All set" screen with a broken core feature.
    @Published var notificationDenied = false

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
        let trimmed = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "Please enter a family name")
            return
        }
        guard trimmed.count <= 100 else {
            errorMessage = String(localized: "Family name must be 100 characters or fewer")
            return
        }
        familyName = trimmed

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

    /// Valid when a name is present and the phone has at least 10 digits — drives
    /// the Send Invite button so we don't submit "abc" or a 3-digit number.
    var canInviteReceiver: Bool {
        !receiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && receiverPhone.filter(\.isNumber).count >= 10
    }

    func inviteReceiver() async {
        guard let family = createdFamily else {
            errorMessage = String(localized: "Please fill in all fields")
            return
        }
        let trimmedName = receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = String(localized: "Please enter their name")
            return
        }
        guard receiverPhone.filter(\.isNumber).count >= 10 else {
            errorMessage = String(localized: "Please enter a valid phone number")
            return
        }
        receiverName = trimmedName

        isLoading = true
        errorMessage = nil

        // Wire format for the backend — POSIX-locked so user region settings can't
        // alter the 24h "HH:mm" contract (e.g. Arabic-Indic digits) — US-IOS044.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
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
        let granted = (try? await PushNotificationService.shared.requestPermission()) ?? false
        if granted {
            notificationDenied = false
            advance()
        } else {
            // Don't auto-advance: keep the user on this step so they can recover via
            // Open Settings, or make a deliberate choice to continue without alerts.
            notificationDenied = true
        }
    }

    /// User explicitly chose to proceed without notifications after being warned.
    func continuePastNotifications() {
        advance()
    }
}
