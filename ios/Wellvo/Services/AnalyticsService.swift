import Foundation
import TelemetryDeck

/// Privacy-first analytics using TelemetryDeck.
/// No personal data is collected — only anonymous usage signals.
/// TelemetryDeck is GDPR-compliant and does not use cookies or fingerprinting.
///
/// Usage: AnalyticsService.shared.track(.checkIn)
actor AnalyticsService {
    static let shared = AnalyticsService()

    private var isInitialized = false

    // MARK: - Event Names

    enum Event: String {
        // Auth
        case signIn = "auth.sign_in"
        case signUp = "auth.sign_up"
        case signOut = "auth.sign_out"

        // Check-in
        case checkIn = "checkin.completed"
        case checkInOffline = "checkin.offline_queued"
        case checkInOfflineSynced = "checkin.offline_synced"
        case moodSubmitted = "checkin.mood_submitted"

        // Owner actions
        case dashboardViewed = "owner.dashboard_viewed"
        case onDemandCheckInSent = "owner.on_demand_sent"
        case receiverInvited = "owner.receiver_invited"
        case receiverRemoved = "owner.receiver_removed"
        case settingsSaved = "owner.settings_saved"
        case reportExported = "owner.report_exported"
        case historyViewed = "owner.history_viewed"

        // Subscription
        case subscriptionStarted = "subscription.started"
        case subscriptionRestored = "subscription.restored"
        case subscriptionViewOpened = "subscription.view_opened"

        // Onboarding
        case onboardingStarted = "onboarding.started"
        case onboardingCompleted = "onboarding.completed"
        case onboardingStepViewed = "onboarding.step_viewed"

        // Notifications
        case notificationPermissionGranted = "notification.permission_granted"
        case notificationPermissionDenied = "notification.permission_denied"

        // Alerts
        case alertViewed = "alert.viewed"
        case alertDismissed = "alert.dismissed"

        // App lifecycle
        case appOpened = "app.opened"
        case appBackgrounded = "app.backgrounded"
    }

    // MARK: - Initialization

    /// Initialize TelemetryDeck with the app ID from build config.
    /// Call this once in WellvoApp.init().
    func initialize() {
        #if !DEBUG
        let appID = Configuration.telemetryAppID
        guard !appID.isEmpty else { return }
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        isInitialized = true
        #endif
    }

    // MARK: - Tracking

    /// Track an analytics event with optional metadata.
    /// All data is anonymous — no user IDs or personal info.
    func track(_ event: Event, properties: [String: String] = [:]) {
        guard isInitialized else { return }

        TelemetryDeck.signal(event.rawValue, parameters: properties)
    }

    /// Track a screen view.
    func trackScreen(_ name: String) {
        track(.dashboardViewed, properties: ["screen": name])
    }
}
