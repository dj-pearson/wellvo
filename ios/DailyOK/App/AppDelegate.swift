import UIKit
import UserNotifications
import os

/// Where a tapped notification action should route. Extracted from the
/// `didReceive` handler so the action-identifier → behavior mapping is a pure,
/// unit-testable function (US-IOS110) instead of an inline switch buried in a
/// UNUserNotificationCenterDelegate callback.
enum NotificationRoute: Equatable {
    /// A check-in response of the given type (I'm OK / Need Help / Call Me).
    case checkIn(CheckInResponseType)
    /// Defer escalation without opening the app.
    case snooze
    /// Owner taps "Call Now" on an urgent alert.
    case callReceiver
    /// Owner/viewer taps "View Details" on a location, battery or missed
    /// check-in alert — open the app on the dashboard.
    case viewDetails
    /// Body tap / default action — open the app (and confirm delivery).
    case openApp
    /// An action this build doesn't handle.
    case none

    /// Caregiver alerts whose body tap should land on the dashboard — where the
    /// card, its Call button and "I've got this" are — instead of whichever tab
    /// was open last (a co-caregiver left on Settings tapped "Mom needs help"
    /// and landed on Settings).
    static let dashboardAlertTypes: Set<String> = [
        "need_help", "call_me", "sos", "owner_alert", "viewer_alert",
        "geofence_alert", "low_battery_alert", "picking_me_up", "can_stay_longer",
        "escalation_resolved", "checkin_confirmed",
    ]
    static let dashboardCategories: Set<String> = ["URGENT_ALERT", "KID_RESPONSE", "LOCATION_ALERT"]

    static func opensDashboard(type: String?, category: String?) -> Bool {
        if let type, dashboardAlertTypes.contains(type) { return true }
        if let category, dashboardCategories.contains(category) { return true }
        return false
    }

    /// Map a `UNNotificationResponse.actionIdentifier` to a route. Mirrors the
    /// categories registered in `NotificationCategories.register()`.
    static func route(for actionIdentifier: String) -> NotificationRoute {
        switch actionIdentifier {
        case "CHECKIN_OK_ACTION": return .checkIn(.ok)
        case "CHECKIN_NEED_HELP_ACTION": return .checkIn(.needHelp)
        case "CHECKIN_CALL_ME_ACTION": return .checkIn(.callMe)
        case "CHECKIN_SNOOZE_ACTION": return .snooze
        case "CALL_RECEIVER_ACTION": return .callReceiver
        case "VIEW_LOCATION_ACTION": return .viewDetails
        case UNNotificationDefaultActionIdentifier: return .openApp
        default: return .none
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Posted when a notification action asks for the dashboard. The delegate
    /// has no route to the SwiftUI environment, so ContentView observes this and
    /// moves the tab — the same bridge the app already uses for offline-sync
    /// completion.
    static let showDashboardRequested = Notification.Name("DailyOK.showDashboardRequested")
    /// userInfo keys on showDashboardRequested: an explanation to show once the
    /// dashboard is up (e.g. "Call Now" couldn't find a number).
    static let outcomeTitleKey = "outcome_title"
    static let outcomeMessageKey = "outcome_message"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationCategories.register()
        // Heartbeat is started/stopped with the authenticated session lifecycle
        // (see AuthViewModel.checkSession / signOut and the scene background
        // handler) rather than unconditionally at launch, so a signed-out user
        // doesn't keep heart-beating.

        // Activate the Apple Watch session so the wrist app receives the latest
        // check-in snapshot and can report wrist check-ins back to the phone.
        PhoneWatchSync.shared.activate()

        // Observe wrist check-ins for the app lifetime. The hand-off was fully
        // wired (watch -> didReceiveWatchCheckIn) but nothing listened, so a
        // wrist check-in was invisible to the phone: its snapshot still said
        // not-checked-in (could re-escalate) and the widgets didn't update
        // (US-IOS082). On notify, optimistically mark today done (this also
        // reloads all widget timelines + re-syncs the watch) and broadcast a
        // refresh so a foregrounded receiver view reloads its status.
        //
        // Only a report of a check-in that REACHED THE SERVER and answered
        // TODAY marks today done — and then through the full aftermath, so the
        // fallback reminder is cancelled and the "please check in" banners are
        // cleared, as for any other surface. The bare notify this replaces was
        // also sent for a tap merely queued on the watch, or a marker from an
        // earlier day being flushed, and marked today done on the phone, the
        // widget and (synced back) the watch — which then refused the real
        // check-in. Anything else just asks an open home screen to reload.
        NotificationCenter.default.addObserver(
            forName: PhoneWatchSync.didReceiveWatchCheckIn,
            object: nil,
            queue: .main
        ) { note in
            let report = WatchCheckInReport(userInfo: note.userInfo ?? [:])
            let calendar = SharedCheckInStore.load()?.receiverCalendar ?? .current
            guard let report, report.answersToday(calendar: calendar) else { return }
            Task { @MainActor in
                await ReceiverCheckInAftermath.record(
                    at: report.answeredAt,
                    helpKind: report.type == "ok" ? nil : report.type
                )
            }
        }

        // Sync access token to shared App Group for Notification Service Extension
        Task { await SupabaseService.shared.syncAccessTokenToExtension() }

        // Register for remote notifications at cold launch when permission is
        // already granted (reinstall / restore-from-backup, where no new
        // permission prompt fires and the initial scenePhase transition may not
        // re-trigger registration). Idempotent with the resume-path
        // registration — APNs returns the same token and registerToken upserts —
        // so this just guarantees an already-granted user gets a live token
        // without first having to background and foreground the app (US-IOS121).
        Task {
            if await PushNotificationService.shared.checkPermissionStatus() == .authorized {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            do {
                try await PushNotificationService.shared.registerToken(token)
            } catch {
                Log.push.error("Token registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Log.push.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Confirm delivery when notification arrives on device
        let userInfo = notification.request.content.userInfo
        if let requestId = userInfo["checkin_request_id"] as? String {
            Task {
                await CheckInService.shared.confirmDelivery(checkinRequestId: requestId)
            }
        }
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch NotificationRoute.route(for: response.actionIdentifier) {
        case .checkIn(let responseType):
            // "I'm OK" runs in the background now. iOS keeps the app alive only
            // until completionHandler is called, so call it when the check-in
            // has actually been sent (or queued) — not before.
            Task { @MainActor in
                // A background action gets roughly 30 seconds. Ask for the
                // standard extra time so a slow network can still finish or
                // fall back to the offline queue instead of being cut off.
                let taskId = UIApplication.shared.beginBackgroundTask(withName: "notification-check-in")
                await handleCheckInFromNotification(userInfo: userInfo, responseType: responseType)
                completionHandler()
                if taskId != .invalid { UIApplication.shared.endBackgroundTask(taskId) }
            }
            return
        case .snooze:
            // Same for the background snooze: calling completionHandler first
            // let iOS suspend the app before the snooze reached the server.
            Task { @MainActor in
                await handleSnoozeFromNotification(userInfo: userInfo)
                completionHandler()
            }
            return
        case .callReceiver:
            handleCallReceiver(userInfo: userInfo)
        case .viewDetails:
            // The action carries `.foreground`, so iOS is already opening the
            // app; make sure it lands on the dashboard rather than wherever the
            // owner last was. Previously this fell through to `.none` and the
            // button opened the app to a stale screen.
            NotificationCenter.default.post(name: AppDelegate.showDashboardRequested, object: nil)
        case .openApp:
            // User tapped notification body — open app and confirm delivery.
            if let requestId = userInfo["checkin_request_id"] as? String {
                Task { await CheckInService.shared.confirmDelivery(checkinRequestId: requestId) }
            }
            if NotificationRoute.opensDashboard(
                type: userInfo["type"] as? String,
                category: response.notification.request.content.categoryIdentifier
            ) {
                NotificationCenter.default.post(name: AppDelegate.showDashboardRequested, object: nil)
            }
        case .none:
            break
        }

        completionHandler()
    }

    // MARK: - Private

    private func handleCallReceiver(userInfo: [AnyHashable: Any]) {
        // Look up the receiver's phone number and initiate a call. The action
        // is `.foreground`, so the app is already opening: any failure lands
        // on the dashboard (where the card's Call button is) with a reason,
        // instead of an unrelated screen and nothing happening.
        guard let receiverIdString = userInfo["receiver_id"] as? String,
              let receiverId = UUID(uuidString: receiverIdString) else {
            AppDelegate.showCallFailure(message: String(localized: "Open their card on the dashboard to call them."))
            return
        }

        Task {
            do {
                // Fetch receiver's phone number
                let users: [AppUser] = try await SupabaseService.shared.client
                    .from("users")
                    .select("id, phone")
                    .eq("id", value: receiverId.uuidString)
                    .limit(1)
                    .execute()
                    .value

                // Normalize to a tel:// URL (dialable characters only).
                let cleaned = (users.first?.phone ?? "")
                    .replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                guard !cleaned.isEmpty, let telURL = URL(string: "tel://\(cleaned)") else {
                    Log.general.error("No phone number found for receiver")
                    AppDelegate.showCallFailure(message: String(localized: "There's no phone number on file for them. Open their card on the dashboard for other ways to reach them."))
                    return
                }

                await MainActor.run {
                    UIApplication.shared.open(telURL) { opened in
                        if !opened {
                            AppDelegate.showCallFailure(message: String(localized: "This device can't place calls. Open their card on the dashboard for other ways to reach them."))
                        }
                    }
                }
            } catch {
                // Don't let an urgent "Call Now" action silently no-op on a query
                // failure (offline / RLS) — the previous bare `try` discarded the
                // throw entirely.
                Log.general.error("Call-receiver lookup failed: \(error.localizedDescription, privacy: .public)")
                AppDelegate.showCallFailure(message: String(localized: "Couldn't look up their number — check your connection. Tap Call on their card on the dashboard."))
            }
        }
    }

    /// "Call Now" couldn't start a call: open the dashboard and say why.
    private static func showCallFailure(message: String) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: AppDelegate.showDashboardRequested,
                object: nil,
                userInfo: [
                    AppDelegate.outcomeTitleKey: String(localized: "Couldn't start the call"),
                    AppDelegate.outcomeMessageKey: message,
                ]
            )
        }
    }

    @MainActor
    private func handleSnoozeFromNotification(userInfo: [AnyHashable: Any]) async {
        if let requestIdString = userInfo["checkin_request_id"] as? String,
           let requestId = UUID(uuidString: requestIdString) {
            // Defer escalation server-side (best-effort; bounded server-side).
            do {
                try await CheckInService.shared.snoozeCheckIn(requestId: requestId)
            } catch {
                Log.checkIn.error("Notification snooze failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Re-arm the local fallback reminder regardless, so the receiver is
        // nudged again in 15 minutes even if the snooze POST didn't land.
        await PushNotificationService.shared.scheduleLocalCheckinFallback(
            at: Date().addingTimeInterval(15 * 60),
            isKidMode: false
        )
    }

    /// The family this device's receiver checks in to, without a network call:
    /// from the shared snapshot the app publishes on every status load. The
    /// offline path used to call FamilyService.getFamily(), which needs the
    /// network — so exactly the check-ins that needed queueing were dropped.
    @MainActor
    private func cachedReceiverFamilyId() -> UUID? {
        SharedCheckInStore.load().flatMap { UUID(uuidString: $0.familyId) }
    }

    @MainActor
    private func handleCheckInFromNotification(userInfo: [AnyHashable: Any], responseType: CheckInResponseType) async {
        // Which scheduled window this notification is chasing (US-IOS138). Used
        // ONLY where the server can't read it off the request: online,
        // respondToCheckIn identifies the check-in by request id and the server
        // reads the slot from the request itself, which is authoritative.
        let slotKey = userInfo["slot_key"] as? String

        guard let requestId = userInfo["checkin_request_id"] as? String else {
            // The app's own local fallback reminder carries no request id. Its
            // "I'm OK" used to do nothing at all (masked while the action opened
            // the app); check in directly instead.
            await checkInWithoutRequest(responseType: responseType, slotKey: slotKey)
            return
        }

        do {
            // Location only when the app is on screen. From a Lock Screen tap
            // the app runs in the background, where a location fix can take up
            // to its 15s timeout (or never come with While-Using permission) —
            // time the check-in itself needs.
            let location = UIApplication.shared.applicationState == .active
                ? await LocationService.shared.getCurrentLocation()
                : nil

            UIDevice.current.isBatteryMonitoringEnabled = true
            let batteryLevel = UIDevice.current.batteryLevel
            let battery: Double? = batteryLevel >= 0 ? Double(batteryLevel) : nil

            try await CheckInService.shared.respondToCheckIn(
                requestId: requestId,
                source: .notification,
                responseType: responseType,
                location: location,
                batteryLevel: battery
            )
            await ReceiverCheckInAftermath.record(at: Date(), helpKind: Self.helpKind(for: responseType))
            if responseType != .ok {
                // The help action no longer opens the app, so say it went.
                await PushNotificationService.shared.presentHelpSent(
                    callMe: responseType == .callMe,
                    ownerName: SharedCheckInStore.load()?.ownerName
                )
            }
        } catch {
            Log.checkIn.error("Notification check-in response failed: \(error.localizedDescription, privacy: .public)")
            // Decide offline-vs-hard-error from the ERROR itself, not the
            // asynchronously-updated `isOnline` flag — NWPathMonitor often
            // hasn't flipped to offline yet when the radio drops mid-request.
            // Mirrors `OfflineCheckInService.performCheckIn`.
            let connectivity = OfflineCheckInService.isConnectivityError(error)
            if responseType == .ok, connectivity {
                // Offline plain "I'm OK": persist so it syncs later. The
                // per-slot, per-day dedup on both the queue (US-IOS137) and the
                // edge function keeps this from duplicating a phone check-in.
                if await queueOfflineCheckIn(slotKey: slotKey) {
                    await ReceiverCheckInAftermath.record(at: Date(), savedOffline: true)
                } else {
                    // Couldn't even persist it — don't let the receiver believe
                    // their check-in landed.
                    await PushNotificationService.shared.presentCheckInResponseFailed(urgent: false)
                }
            } else if responseType != .ok {
                // Urgent response (need help / call me) that didn't go through,
                // offline or refused. We deliberately do NOT queue an urgent
                // signal for silent later delivery — it must reach the owner
                // live — but the receiver must always know it didn't send so
                // they can retry or reach out another way. (Only connectivity
                // failures used to say so; a server refusal was silent.)
                await PushNotificationService.shared.presentCheckInResponseFailed(urgent: true)
            }
            // A plain "I'm OK" the server refused (e.g. already resolved) has no
            // phantom-success risk, so no extra alert.
        }
    }

    /// The snapshot's wire value for a help response, nil for "I'm OK".
    static func helpKind(for responseType: CheckInResponseType) -> String? {
        switch responseType {
        case .needHelp: return "need_help"
        case .callMe: return "call_me"
        case .ok: return nil
        }
    }

    /// Queue an offline "I'm OK" for later sync. Needs no network: the family
    /// and receiver come from the shared snapshot. Returns whether it was saved.
    @MainActor
    private func queueOfflineCheckIn(slotKey: String?) async -> Bool {
        guard let snapshot = SharedCheckInStore.load(),
              let familyId = UUID(uuidString: snapshot.familyId),
              let receiverId = UUID(uuidString: snapshot.receiverId) else { return false }
        do {
            try OfflineCheckInService.shared.queueCheckIn(
                familyId: familyId,
                receiverId: receiverId,
                mood: nil,
                source: .notification,
                slotKey: slotKey
            )
            return true
        } catch {
            Log.checkIn.error("Failed to queue offline notification check-in: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Check in from a notification that isn't tied to a server request (the
    /// local fallback reminder).
    @MainActor
    private func checkInWithoutRequest(responseType: CheckInResponseType, slotKey: String?) async {
        guard let familyId = cachedReceiverFamilyId() else {
            // Nothing to check in to on this device (not a receiver, or the app
            // has never loaded). The receiver must hear that it didn't send.
            await PushNotificationService.shared.presentCheckInResponseFailed(urgent: responseType != .ok)
            return
        }
        if responseType == .ok {
            do {
                // nil = queued on this phone rather than sent.
                let row = try await OfflineCheckInService.shared.performCheckIn(
                    familyId: familyId,
                    source: .notification,
                    slotKey: slotKey
                )
                await ReceiverCheckInAftermath.record(at: row?.checkedInAt ?? Date(), savedOffline: row == nil)
            } catch is NetworkError {
                // Queued for sync by performCheckIn.
                await ReceiverCheckInAftermath.record(at: Date(), savedOffline: true)
            } catch {
                Log.checkIn.error("Fallback-reminder check-in failed: \(error.localizedDescription, privacy: .public)")
                await PushNotificationService.shared.presentCheckInResponseFailed(urgent: false)
            }
        } else {
            // Need help / call me: must reach the owner live, never queued.
            do {
                _ = try await CheckInService.shared.checkIn(
                    familyId: familyId,
                    source: .notification,
                    responseType: responseType,
                    slotKey: slotKey
                )
                await ReceiverCheckInAftermath.record(at: Date(), helpKind: Self.helpKind(for: responseType))
                await PushNotificationService.shared.presentHelpSent(
                    callMe: responseType == .callMe,
                    ownerName: SharedCheckInStore.load()?.ownerName
                )
            } catch {
                Log.checkIn.error("Fallback-reminder urgent response failed: \(error.localizedDescription, privacy: .public)")
                await PushNotificationService.shared.presentCheckInResponseFailed(urgent: true)
            }
        }
    }
}

/// The notification categories and their actions. Its own type so the
/// check-in category can be re-registered when the biometric setting changes.
enum NotificationCategories {
    static func register() {
        // Background: one tap on the Lock Screen checks in without opening the
        // app. It used to be `.foreground`, which opened the app on a home screen
        // still showing "I'm OK" while the check-in was in flight, so receivers
        // tapped twice. The session is readable while locked (AfterFirstUnlock),
        // so no unlock is needed either — unless the receiver turned on Face ID
        // lock: then "I'm OK" and snooze ask for Face ID / passcode first, the
        // same promise the widget, Control Center and Siri keep (tokens
        // withheld while locked). Help actions never do; see below.
        let biometricLock = BiometricService.isEnabledPreference
        let routineOptions: UNNotificationActionOptions = biometricLock ? [.authenticationRequired] : []

        let okAction = UNNotificationAction(
            identifier: "CHECKIN_OK_ACTION",
            title: "I'm OK ✓",
            options: routineOptions
        )

        // Background too, with no unlock. A parent who has fallen — shaking
        // hands, Face ID failing — had to unlock the phone before "I Need Help"
        // was sent, while "I'm OK" needed nothing. The response goes out live
        // through handleCheckInFromNotification, which tells the receiver both
        // when it was sent and when it wasn't. Actions only appear on a long
        // press of the notification, and the server folds a repeat within two
        // minutes into one alert, so a pocket tap can't page the family twice.
        let needHelpAction = UNNotificationAction(
            identifier: "CHECKIN_NEED_HELP_ACTION",
            title: "I Need Help",
            options: [.destructive]
        )

        let callMeAction = UNNotificationAction(
            identifier: "CHECKIN_CALL_ME_ACTION",
            title: "Call Me",
            options: []
        )

        // Background snooze — defers escalation without opening the app.
        let snoozeAction = UNNotificationAction(
            identifier: "CHECKIN_SNOOZE_ACTION",
            title: "Remind me in 15 min",
            options: routineOptions
        )

        // Help before "remind me": in distress, the second button is the one
        // that should say "help".
        let checkinCategory = UNNotificationCategory(
            identifier: "CHECKIN_REQUEST",
            actions: [okAction, needHelpAction, callMeAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        // Urgent alert category for owners (call me / need help alerts)
        let callNowAction = UNNotificationAction(
            identifier: "CALL_RECEIVER_ACTION",
            title: "Call Now",
            options: [.foreground]
        )

        let urgentAlertCategory = UNNotificationCategory(
            identifier: "URGENT_ALERT",
            actions: [callNowAction],
            intentIdentifiers: [],
            options: []
        )

        // Kid-mode responses to a parent: "pick me up", "can I stay longer".
        // The server has always sent `category: "KID_RESPONSE"` and the app has
        // never registered it, so the parent got a bare banner with no way to
        // act — on a message whose whole point is that their child wants
        // something now. The payload carries `receiver_id`, which is what
        // CALL_RECEIVER_ACTION needs.
        let kidResponseCategory = UNNotificationCategory(
            identifier: "KID_RESPONSE",
            actions: [callNowAction],
            intentIdentifiers: [],
            options: []
        )

        // Location/battery alert category for owners
        let viewLocationAction = UNNotificationAction(
            identifier: "VIEW_LOCATION_ACTION",
            title: "View Details",
            options: [.foreground]
        )

        let locationAlertCategory = UNNotificationCategory(
            identifier: "LOCATION_ALERT",
            actions: [viewLocationAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            checkinCategory,
            urgentAlertCategory,
            kidResponseCategory,
            locationAlertCategory,
        ])
    }
}

/// What the watch reported about a wrist check-in (PhoneWatchSync hand-off).
/// Pure, for tests.
struct WatchCheckInReport: Equatable {
    let answeredAt: Date
    let type: String

    /// nil for anything that isn't a delivered check-in: the bare legacy
    /// `["watch_checked_in": true]` (an older watch build also sent it for a
    /// queued tap), or a report without a time.
    init?(userInfo: [AnyHashable: Any]) {
        guard (userInfo["sent"] as? Bool) == true,
              let at = (userInfo["answered_at"] as? NSNumber)?.doubleValue else { return nil }
        answeredAt = Date(timeIntervalSince1970: at)
        let raw = (userInfo["type"] as? String) ?? "ok"
        type = ["ok", "need_help", "call_me"].contains(raw) ? raw : "ok"
    }

    init(answeredAt: Date, type: String) {
        self.answeredAt = answeredAt
        self.type = type
    }

    /// Whether it answers today (in the receiver's zone), and isn't in the
    /// future.
    func answersToday(now: Date = Date(), calendar: Calendar) -> Bool {
        answeredAt <= now.addingTimeInterval(60) && calendar.isDate(answeredAt, inSameDayAs: now)
    }
}
