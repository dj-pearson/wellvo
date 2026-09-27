import SwiftUI

@MainActor
final class AppState: ObservableObject {
    /// An invite link's token waiting to be redeemed. Persisted: the receiver
    /// usually taps the link, then has to sign in (and may leave the app to read
    /// the SMS code) — a token held only in memory was lost if iOS killed the
    /// app in between, and they landed with no family.
    @Published var pendingInviteToken: String? {
        didSet { UserDefaults.standard.set(pendingInviteToken, forKey: Self.pendingInviteTokenKey) }
    }
    @Published var pendingAutoJoin: AutoJoinResult?
    @Published var currentUserRole: UserRole?

    /// Where launch routing stands on `currentUserRole`.
    ///
    /// `nil` role used to mean both "still loading / lookup failed" and "no
    /// family yet", and both fell through to the owner's tabs — so a receiver
    /// who opened the app offline saw owner screens. ContentView now only treats
    /// a nil role as "new here" once the lookup has actually `.resolved`.
    enum RoleResolution: Equatable {
        case resolving
        case resolved
        case failed
    }
    @Published var roleResolution: RoleResolution = .resolving
    @Published var selectedTab: AppTab = .dashboard
    @Published var isOnboarding: Bool = false
    @Published var showPairingCodeEntry: Bool = false

    /// "Have a setup code?" was tapped on the sign-in screen. Sign-in has to
    /// come first, so this is remembered and acted on once role resolution
    /// finds no membership (an existing member never gets the code screen
    /// over their home). The tap used to set a flag nothing on screen read.
    @Published var setupCodeAfterSignIn: Bool = false

    /// The verified phone matched an invite, but the family's plan has no
    /// free place. Shown on the get-started screen instead of dropping the
    /// person there with no reason (where "Set up check-ins for someone"
    /// would make them the owner of an empty family by mistake).
    @Published var autoJoinBlockedMessage: String?

    /// When role resolution last got an answer from the server, so a return
    /// to the foreground can re-check a role that may have changed (removed
    /// from the family, made owner) without a cold launch.
    var lastRoleResolvedAt: Date?

    /// Asks ContentView to resolve the role again (e.g. a join whose answer
    /// was lost may in fact have succeeded).
    @Published var roleRefreshRequest = 0

    /// Set when the launch/resume pin probe finds a genuine certificate
    /// mismatch (a device-trusted but un-pinned CA — possible MITM). Drives a
    /// blocking overlay; transient "couldn't evaluate" states never set this.
    @Published var secureConnectionFailed: Bool = false

    /// Covers the UI while the app is leaving the foreground, when the user
    /// relies on biometric lock.
    ///
    /// iOS captures the App Switcher snapshot during the `.inactive` window and
    /// keeps it on disk. Raising the biometric lock only on resume meant that
    /// snapshot was taken of the live dashboard, so anyone holding the phone
    /// could read a relative's status, location and care notes from the switcher
    /// card without ever passing Face ID — the one thing the lock is for.
    ///
    /// Deliberately separate from `AuthViewModel.biometricLocked`: this only
    /// obscures pixels. Raising the real lock here would re-enter the unlock
    /// prompt on every transient interruption, including the Face ID sheet's own.
    @Published var privacyCoverActive: Bool = false

    /// Result of a deep link that performed an ACTION rather than navigation —
    /// today, the escalation Live Activity's "Stand down" button.
    ///
    /// It used to only log. The owner taps Stand down on an overdue relative,
    /// the app opens, nothing visible happens, and if the call failed the
    /// escalation is still running while they believe they cancelled it. An
    /// action taken on someone's behalf has to report whether it happened.
    @Published var deepLinkOutcome: DeepLinkOutcome?

    /// A stand-down asked for from outside the app — the escalation Live
    /// Activity's "Stand down" button (`dailyok://standdown`). Never acted on
    /// directly: the URL scheme is public, so any link (a text from a family
    /// member, a web page) could otherwise cancel an escalation on a
    /// caregiver's phone with one tap. The dashboard shows the same "Stop
    /// alerts for X?" confirmation as the card, and only for a receiver who is
    /// escalating in the loaded family, to its owner or an active co-caregiver.
    @Published var pendingStandDown: PendingStandDown?

    /// A "Text" tapped on a caregiver alert: the dashboard opens Messages
    /// pre-filled for this receiver once their card has loaded (and says so
    /// when there's no number to text).
    @Published var pendingTextReceiver: UUID?

    struct PendingStandDown: Equatable {
        let receiverId: UUID
        let familyId: UUID
    }

    struct DeepLinkOutcome: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
        let isFailure: Bool
    }

    /// Non-essential haptics (selection, light, medium). Outcome haptics
    /// (success/warning/error) always fire so users don't miss a failure.
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "dailyok.haptics.enabled") }
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: "dailyok.haptics.enabled") as? Bool
        self.hapticsEnabled = stored ?? true
        self.pendingInviteToken = UserDefaults.standard.string(forKey: Self.pendingInviteTokenKey)
    }

    private static let pendingInviteTokenKey = "dailyok.pendingInviteToken"
    private static let cachedRoleKeyPrefix = "dailyok.cachedRole."

    /// The last role this user was routed with on this device, so a launch with
    /// no network still opens the right app (a receiver's check-in button, not
    /// an owner dashboard). Keyed per user so a sign-in as someone else never
    /// inherits it.
    func cachedRole(for userId: UUID) -> UserRole? {
        UserDefaults.standard.string(forKey: Self.cachedRoleKeyPrefix + userId.uuidString)
            .flatMap(UserRole.init(rawValue:))
    }

    func cacheRole(_ role: UserRole?, for userId: UUID) {
        let key = Self.cachedRoleKeyPrefix + userId.uuidString
        if let role {
            UserDefaults.standard.set(role.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Declined phone-match invites

    private static let declinedAutoJoinKeyPrefix = "dailyok.declinedAutoJoin."

    /// Families this user said "This isn't me" to when their phone number
    /// matched an invite. Not offered again on this device, so a wrong-number
    /// invite doesn't reappear on every launch.
    func hasDeclinedAutoJoin(familyId: String, for userId: UUID) -> Bool {
        let key = Self.declinedAutoJoinKeyPrefix + userId.uuidString
        return (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(familyId)
    }

    func declineAutoJoin(familyId: String, for userId: UUID) {
        let key = Self.declinedAutoJoinKeyPrefix + userId.uuidString
        var declined = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !declined.contains(familyId) else { return }
        declined.append(familyId)
        UserDefaults.standard.set(Array(declined.suffix(20)), forKey: key)
    }

    /// Everything in progress for a signed-in person that must not carry over
    /// to whoever signs in next on this device.
    func resetForSignOut() {
        currentUserRole = nil
        roleResolution = .resolving
        pendingInviteToken = nil
        pendingAutoJoin = nil
        isOnboarding = false
        showPairingCodeEntry = false
        setupCodeAfterSignIn = false
        autoJoinBlockedMessage = nil
        lastRoleResolvedAt = nil
        pendingTextReceiver = nil
    }

    enum AppTab: Int, CaseIterable {
        case dashboard = 0
        case history = 1
        case family = 2
        case settings = 3
    }
}
