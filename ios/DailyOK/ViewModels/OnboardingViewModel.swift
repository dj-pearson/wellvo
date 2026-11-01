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

/// The family-creation calls the onboarding step makes, as a seam so tests can
/// assert that going Back and tapping Continue again — or retrying after a
/// failed membership insert — never inserts a second `families` row. A
/// duplicate orphaned the receiver: invites targeted the new family while
/// `getFamily()` resolved to the earliest one, so the receiver never appeared.
///
/// Deliberately narrow, like `SignOutDependencies`.
struct OnboardingFamilyDependencies {
    /// The caller's earliest owned family, if any (never a family they only
    /// belong to as a receiver/viewer).
    var findOwnedFamily: @MainActor () async throws -> Family?
    var insertFamily: @MainActor (_ name: String) async throws -> Family
    var renameFamily: @MainActor (_ id: UUID, _ name: String) async throws -> Family
    /// Idempotent: a no-op when the owner's membership row already exists.
    var ensureOwnerMembership: @MainActor (_ familyId: UUID) async throws -> Void

    @MainActor
    static var live: OnboardingFamilyDependencies {
        OnboardingFamilyDependencies(
            findOwnedFamily: { try await FamilyService.shared.ownedFamily() },
            insertFamily: { name in try await FamilyService.shared.insertFamily(name: name) },
            renameFamily: { id, name in try await FamilyService.shared.renameFamily(id: id, name: name) },
            ensureOwnerMembership: { familyId in try await FamilyService.shared.ensureOwnerMembership(familyId: familyId) }
        )
    }
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
    /// Set once the invite record is created; drives the native Messages composer
    /// so the invite is sent from the owner's own number (not our Twilio A2P
    /// number). The step only advances after the composer reports a real send.
    @Published var pendingInvite: InviteDetails?

    var createdFamily: Family?

    /// Overridden by tests; nil means the live FamilyService.
    var familyDependencies: OnboardingFamilyDependencies?

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
        guard !isLoading else { return }
        familyName = trimmed

        isLoading = true
        errorMessage = nil

        let deps = familyDependencies ?? .live
        do {
            // Never insert a second family. Reuse, in order: the family this
            // onboarding run already made (the owner went Back and tapped
            // Continue again, or the membership insert failed last time), then
            // one the owner already has on the server (e.g. a run that was
            // killed mid-way). Only with neither is a new row inserted.
            var family: Family
            if let existing = createdFamily {
                family = existing
            } else if let owned = try await deps.findOwnedFamily() {
                family = owned
            } else {
                family = try await deps.insertFamily(familyName)
            }
            // Remember it before anything else can fail, so a retry reuses it.
            createdFamily = family

            if family.name != familyName {
                family = try await deps.renameFamily(family.id, familyName)
                createdFamily = family
            }

            try await deps.ensureOwnerMembership(family.id)
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
            errorMessage = edgeErrorMessage(error, fallback: error.localizedDescription)
        }

        isLoading = false
    }

    /// Called when the native invite composer closes. Advance only on a real
    /// send; otherwise keep the owner on the form so they can try again (the
    /// invite record already exists, so a resend just re-composes the text).
    func handleInviteComposerFinish(sent: Bool) {
        if sent {
            errorMessage = nil
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
