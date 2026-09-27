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
    /// 8:00 AM, like the first-receiver walkthrough and the server's default.
    /// It used to start at "now", so an owner setting up at 11:47 PM who didn't
    /// touch the picker scheduled their parent's reminder for 11:47 PM.
    @Published var checkinTime = OnboardingViewModel.defaultCheckinTime
    /// The owner's own name, asked for when the account has none (phone and
    /// Apple sign-ups get the placeholder "User"). It is what the invitee sees:
    /// "Sarah will see when you check in", not "User".
    @Published var ownerName = ""
    @Published var needsOwnerName = false
    /// The first invite went out during onboarding.
    @Published var didSendInvite = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// True once the user has been asked for notification permission and denied it.
    /// Drives the inline recovery UI (Open Settings / Continue anyway) instead of
    /// silently walking the user into the "All set" screen with a broken core feature.
    @Published var notificationDenied = false
    /// Set once the invite record is created; drives the native Messages composer
    /// so the invite is sent from the owner's own number (not our Twilio A2P
    /// number). The step only advances after the composer reports a real send.
    @Published var pendingInvite: InviteDetails?

    var createdFamily: Family?

    nonisolated static var defaultCheckinTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// Ask for the owner's name only when the account has no real one.
    func loadOwnerName() async {
        let current = await FamilyService.shared.myDisplayName()
        // Unknown (offline) is not "no name": don't ask, and so never
        // overwrite a real name with a guess.
        guard current.loaded else { return }
        if let name = JoinPreview.presentableName(current.name) {
            ownerName = name
            needsOwnerName = false
        } else {
            needsOwnerName = true
        }
    }

    var canCreateFamily: Bool {
        !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!needsOwnerName || !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

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

        let trimmedOwner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsOwnerName {
            guard !trimmedOwner.isEmpty else {
                errorMessage = String(localized: "Please enter your name")
                return
            }
            guard trimmedOwner.count <= 100 else {
                errorMessage = String(localized: "Your name must be 100 characters or fewer")
                return
            }
        }

        isLoading = true
        errorMessage = nil

        do {
            if needsOwnerName {
                try await FamilyService.shared.updateMyDisplayName(trimmedOwner)
                ownerName = trimmedOwner
                needsOwnerName = false
            }
            if let existing = createdFamily {
                // Back from Plans to this step: rename, never create a second
                // family (the dashboard shows the first; invites would go to
                // the second).
                if existing.name != familyName {
                    createdFamily = try await FamilyService.shared.renameFamily(id: existing.id, to: familyName)
                }
            } else {
                // FamilyService.createFamily reuses a family this account
                // already owns (a retry after a half-finished attempt).
                createdFamily = try await FamilyService.shared.createFamily(name: familyName)
            }
            advance()
        } catch {
            errorMessage = AuthService.isConnectivityError(error)
                ? String(localized: "Couldn't reach Daily OK. Check your connection and try again.")
                : String(localized: "Couldn't save your family. Please try again.")
        }

        isLoading = false
    }

    /// Onboarding is finished. When the first invite already went out, the
    /// dashboard must not open "Add your first family member" over it (the
    /// invitee hasn't joined yet, so the family still looks empty) — a second
    /// invite to the same number would expire the text they already have.
    func markFirstInviteHandled() {
        guard didSendInvite, let userId = AuthService.shared.storedUserId else { return }
        let key = "\(DashboardView.walkthroughAutoShownKey).\(userId.uuidString)"
        UserDefaults.standard.set(true, forKey: key)
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
            // Create the invite record, then hand the composed message to the
            // native Messages composer instead of advancing immediately — the
            // owner sends it from their own number.
            pendingInvite = try await FamilyService.shared.inviteReceiver(
                familyId: family.id,
                name: receiverName,
                phone: receiverPhone,
                checkinTime: timeString
            )
        } catch {
            errorMessage = edgeErrorMessage(error, fallback: String(localized: "Couldn't create the invite. Check your connection and try again."))
        }

        isLoading = false
    }

    /// Called when the native invite composer closes. Advance only on a real
    /// send; otherwise keep the owner on the form so they can try again (the
    /// invite record already exists, so a resend just re-composes the text).
    func handleInviteComposerFinish(sent: Bool) {
        if sent {
            errorMessage = nil
            didSendInvite = true
            advance()
        } else {
            errorMessage = String(localized: "Message not sent. Tap Send Invite to try again.")
        }
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
