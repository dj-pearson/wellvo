import SwiftUI
import UIKit
import os
import Supabase

/// Something the receiver can send from the home screen besides "I'm OK".
/// Help / call-me / SOS page the family at once; pickup and stay-longer are
/// kid quick replies. All of them go out live — never through the offline
/// queue — because a help request delivered hours later is worse than one the
/// receiver knows didn't send.
enum ReceiverHelpKind: String, CaseIterable, Identifiable, Equatable {
    case needHelp
    case callMe
    case sos
    case pickMeUp
    case stayLonger

    var id: String { rawValue }

    var responseType: CheckInResponseType {
        switch self {
        case .needHelp: return .needHelp
        case .callMe: return .callMe
        case .sos, .pickMeUp, .stayLonger: return .ok
        }
    }

    var kidResponseType: KidResponseType? {
        switch self {
        case .sos: return .sos
        case .pickMeUp: return .pickingMeUp
        case .stayLonger: return .canStayLonger
        case .needHelp, .callMe: return nil
        }
    }

    /// Pages the family with a critical alert. Confirmed before sending.
    var isUrgent: Bool { self == .needHelp || self == .callMe || self == .sos }

    /// Button title.
    func title(owner: String?) -> String {
        switch self {
        case .needHelp: return String(localized: "I need help")
        case .callMe:
            if let owner { return String(localized: "Ask \(owner) to call me") }
            return String(localized: "Ask my family to call me")
        case .sos: return String(localized: "SOS")
        case .pickMeUp: return String(localized: "Pick me up")
        case .stayLonger: return String(localized: "Can I stay longer?")
        }
    }

    var icon: String {
        switch self {
        case .needHelp: return "exclamationmark.bubble.fill"
        case .callMe: return "phone.arrow.down.left.fill"
        case .sos: return "sos"
        case .pickMeUp: return "car.fill"
        case .stayLonger: return "clock.fill"
        }
    }

    /// The confirmation question for an urgent send.
    func confirmTitle(owner: String?) -> String {
        let who = owner ?? String(localized: "your family")
        switch self {
        case .callMe: return String(localized: "Ask \(who) to call you?")
        default: return String(localized: "Send a help alert to \(who)?")
        }
    }

    /// What was sent, in the receiver's words.
    func sentMessage(owner: String?) -> String {
        let who = owner ?? String(localized: "your family")
        switch self {
        case .needHelp, .sos: return String(localized: "We told \(who) you need help.")
        case .callMe: return String(localized: "We asked \(who) to call you.")
        case .pickMeUp: return String(localized: "We told \(who) you'd like to be picked up.")
        case .stayLonger: return String(localized: "We asked \(who) if you can stay longer.")
        }
    }

    /// The help kind a stored check-in row represents, if any.
    static func from(checkIn: CheckIn) -> ReceiverHelpKind? {
        if checkIn.kidResponseType == KidResponseType.sos.rawValue { return .sos }
        if checkIn.responseType == .needHelp { return .needHelp }
        if checkIn.responseType == .callMe { return .callMe }
        return nil
    }
}

/// An open help request the receiver made, and whether anyone has taken it on.
struct HelpStatus: Equatable {
    let kind: ReceiverHelpKind
    /// When it was sent. nil when only the check-in row is known (a server
    /// without my_open_help_request, 00061).
    let sentAt: Date?
    let acknowledgedBy: String?
    let acknowledgedAt: Date?
}

/// A help send that failed. Shown with a direct call button, never queued.
struct HelpFailure: Equatable {
    let kind: ReceiverHelpKind
    let message: String
}

/// What the home screen offers after a failed check-in.
enum CheckInRecovery: Equatable {
    /// "Try Again" (checks in again).
    case retry
    /// The session is gone; retrying can never work. Offer "Sign in again".
    case signIn
    /// Nothing the receiver can do here (e.g. removed from the family).
    case none
}

@MainActor
final class ReceiverViewModel: ObservableObject {
    /// Nothing is owed right now: today's check-in (or this window's) is done.
    /// False while a later request or window is waiting, even if the receiver
    /// checked in earlier today — see `owesLaterAnswer`.
    @Published var hasCheckedInToday = false
    /// The receiver checked in earlier today, but the family is asking again
    /// (an owner's "check on them now", or the next window of a multi-window
    /// schedule). The home screen shows the button again with "Checked in at
    /// 8:02 AM" above it.
    @Published var owesLaterAnswer = false
    @Published var isCheckingIn = false
    @Published var lastCheckIn: CheckIn?
    /// A failed CHECK-IN, in plain words. Paired with `errorRecovery`.
    @Published var errorMessage: String?
    @Published var errorRecovery: CheckInRecovery = .retry
    /// A failed snooze, undo or setting change. Shown without a retry button:
    /// "Try Again" on a failed snooze used to check the receiver in.
    @Published var actionMessage: String?
    /// A neutral confirmation (undo done, kid reply sent).
    @Published var noticeMessage: String?
    /// Today's check-in is saved on this phone but not yet sent (offline). The
    /// home screen says so instead of "Your family has been notified".
    @Published var checkInSavedOffline = false
    /// Saved because the server was unreachable while the phone was online.
    @Published var savedBecauseServerBusy = false
    @Published var familyId: UUID?
    @Published var familyName: String?
    /// The family owner's first-class name ("Sarah") and phone, for "Call
    /// Sarah" and for copy that names who is told. nil when unknown or a
    /// placeholder.
    @Published var ownerName: String?
    @Published var ownerPhone: String?
    @Published var isOffline = false
    @Published var pendingOfflineCount = 0
    @Published var receiverMode: ReceiverMode = .standard
    /// Senior "Simple Mode": extra-large, low-clutter, emoji-free check-in.
    @Published var simpleMode = false
    /// Speak/chime a confirmation on a successful check-in (low-vision support).
    @Published var audioConfirmationEnabled = false
    @Published var nextCheckInTime: Date?
    @Published var receiverSettings: ReceiverSettings?
    @Published var streakDays: Int = 0
    @Published var consistencyPercent: Int = 0
    /// True when the family is actively waiting on a response (a pending,
    /// unsnoozed checkin_request exists) and the receiver hasn't answered it.
    @Published var hasPendingRequest = false
    /// The newest actively pending request, for the banner and snooze.
    @Published var pendingRequestId: UUID?
    @Published var pendingRequestType: CheckInRequestType?
    @Published var pendingRequestAskedAt: Date?
    @Published var canSnooze = false
    /// Snoozes left on the pending request (server cap 3).
    @Published var snoozesLeft: Int?
    @Published var isSnoozing = false
    /// While in the future, the receiver snoozed and the family won't be
    /// alerted before then. Drives "We'll remind you at 3:45 PM".
    @Published var snoozedUntil: Date?
    /// Mood the receiver picked after checking in (optional, post-check-in).
    @Published var selectedMood: Mood?
    /// While set (and in the future), the just-recorded check-in can still be
    /// undone (US-IOS048). Cleared when the grace window lapses or undo runs.
    @Published var undoableUntil: Date?
    /// True while an undo network call is in flight.
    @Published var isUndoing = false
    /// An open help request (need help / call me / SOS) and who has it.
    @Published var helpStatus: HelpStatus?
    @Published var isSendingHelp = false
    @Published var helpFailure: HelpFailure?

    /// Minutes a snooze defers the request, and the server-side snooze cap.
    nonisolated static let snoozeMinutes = 15
    nonisolated static let maxSnoozes = 3

    /// How long after checking in the receiver may undo an accidental tap.
    /// Kept just under the server-side grace so an in-window tap won't 409.
    nonisolated static let undoGraceSeconds: TimeInterval = 150

    /// How early the button comes back for the next window of a multi-window
    /// day (a tap then is tagged with that window).
    nonisolated static let nextWindowLeadMinutes = 60

    private let offlineService = OfflineCheckInService.shared
    private var loadTask: Task<Void, Never>?
    /// A caller asked for a fresh load while one was running (undo, a check-in
    /// from a notification). The running task does one more pass.
    private var reloadRequested = false
    /// The receiver's own family_member id.
    private var receiverMemberId: UUID?
    /// The receiver's account timezone (users.timezone), captured on load so the
    /// "next check-in" / local-fallback computation buckets in the same zone the
    /// status query and streak chips use — not the device zone, which can differ
    /// when the receiver travels or has a mismatched account timezone.
    private(set) var receiverTimezone: String?
    /// Today's rows, newest first (receiver's zone).
    private var todayCheckIns: [CheckIn] = []
    /// Every pending request for this receiver, newest first.
    private var pendingRequests: [CheckInRequest] = []

    private var receiverCalendar: Calendar { Calendar.forTimezone(receiverTimezone) }

    /// Whether to show the optional "how are you feeling?" picker after a
    /// check-in: enabled in settings, an online check-in row exists to attach to,
    /// and no mood has been recorded yet.
    var shouldPromptForMood: Bool {
        guard receiverSettings?.moodTrackingEnabled == true else { return false }
        guard let checkIn = lastCheckIn, checkIn.mood == nil, !checkIn.isHelpSignal else { return false }
        return selectedMood == nil
    }

    /// Coalesce reload triggers. `loadStatus` is invoked from `.task`,
    /// `scenePhase == .active`, AND the `didSyncCheckIns` observer — and
    /// `loadStatus` itself calls `syncPendingCheckIns()`, which on success posts
    /// `didSyncCheckIns`. Without coalescing, that re-enters `loadStatus` for a
    /// full extra round of queries. Re-entrant callers await the in-flight load.
    ///
    /// `force`: the caller changed server state (undo, a check-in made
    /// elsewhere) and needs a load that STARTS after that change. Returning the
    /// in-flight load's result let a query issued before the undo restore
    /// "You're all set" (and a second Undo 404'd), or skip the reopened
    /// request's banner and reminder. The running task now does one more pass.
    func loadStatus(force: Bool = false) async {
        if let loadTask {
            if force { reloadRequested = true }
            return await loadTask.value
        }
        // Clear the handle from inside the task (via the trailing assignment)
        // rather than after `await task.value`: the caller is usually a view's
        // `.task`, cancelled on disappear. If it's torn down at the suspension
        // below, a caller-side `loadTask = nil` would never run and every later
        // loadStatus() would return the cached completed task instantly — the
        // receiver's status would stop refreshing. The task clears itself.
        let task = Task { [weak self] in
            var passes = 0
            repeat {
                self?.reloadRequested = false
                await self?.performLoadStatus()
                passes += 1
            } while self?.reloadRequested == true && passes < 3
            self?.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func performLoadStatus() async {
        guard let family = try? await FamilyService.shared.getFamily() else {
            // Offline (or the lookup failed): keep the check-in button working.
            // Without a familyId, performCheckIn returned silently — the button
            // did nothing on every offline cold launch, defeating the queue.
            loadCachedStatus()
            return
        }
        familyId = family.id
        familyName = family.name

        guard let session = try? await SupabaseService.shared.client.auth.session else { return }

        struct TimezoneOnly: Decodable { let timezone: String? }
        let tzRow: TimezoneOnly? = try? await SupabaseService.shared.client
            .from("users")
            .select("timezone")
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value
        receiverTimezone = tzRow?.timezone

        await loadOwnerContact(ownerId: family.ownerId)

        // Sync any queued offline check-ins first so the subsequent status
        // query reflects them. Without this, a synced check-in would only
        // appear after the next manual refresh.
        await offlineService.syncPendingCheckIns()

        let rows: [CheckIn]
        do {
            rows = try await CheckInService.shared.todayCheckIns(
                receiverId: session.user.id,
                familyId: family.id,
                timezone: tzRow?.timezone
            )
        } catch {
            // A failed query is not "not checked in". Treating it that way
            // flipped a receiver who had checked in back to "please check in".
            // Keep what we know and let the next load try again.
            Log.receiver.error("todayCheckIns failed: \(error.localizedDescription, privacy: .public)")
            isOffline = !offlineService.isOnline
            pendingOfflineCount = offlineService.pendingCount
            return
        }
        todayCheckIns = rows
        let todayCheckIn = rows.first
        lastCheckIn = todayCheckIn
        // A queued offline check-in that hasn't synced yet still counts on this
        // phone — the receiver did tap, and the queue will deliver it.
        checkInSavedOffline = todayCheckIn == nil
            && hasQueuedCheckInToday(familyId: family.id, receiverId: session.user.id)
        if !checkInSavedOffline { savedBecauseServerBusy = false }
        // A fresh load reflects server truth — clear any locally-picked mood so
        // the prompt reappears only if today's row genuinely has no mood yet.
        selectedMood = todayCheckIn?.mood

        await loadReceiverSettings(userId: session.user.id, familyId: family.id)
        pendingRequests = await loadPendingRequests(receiverId: session.user.id, familyId: family.id)

        let answeredToday = todayCheckIn != nil || checkInSavedOffline
        owesLaterAnswer = answeredToday && Self.owesAnotherAnswer(
            todayCheckIns: rows,
            pendingRequests: pendingRequests,
            settings: receiverSettings,
            calendar: receiverCalendar
        )
        hasCheckedInToday = answeredToday && !owesLaterAnswer
        Log.receiver.debug("loadStatus tz=\(tzRow?.timezone ?? "nil", privacy: .public) rows=\(rows.count, privacy: .public) done=\(self.hasCheckedInToday, privacy: .public) owes=\(self.owesLaterAnswer, privacy: .public)")

        if hasCheckedInToday {
            clearStaleMessages()
            // Answered here, on the widget, the watch or Siri: clear the
            // "please check in" banners still sitting on the Lock Screen.
            await ReceiverCheckInAftermath.removeDeliveredCheckInRequests()
        }
        // Keep the Undo affordance alive across reloads/foregrounds within the
        // grace window, derived from the server check-in time. Never for a
        // help request (it has paged the family; the server refuses) and never
        // while another answer is owed (the card with Undo isn't shown).
        if hasCheckedInToday, let row = todayCheckIn, !row.isHelpSignal {
            let deadline = row.checkedInAt.addingTimeInterval(Self.undoGraceSeconds)
            if deadline > Date() {
                if undoableUntil != deadline { openUndoWindow(deadline: deadline) }
            } else {
                undoableUntil = nil
            }
        } else {
            undoableUntil = nil
        }

        await refreshHelpStatus(familyId: family.id)
        applyPendingRequestState()

        // Load 30-day history for streak + consistency badges on the home header.
        // Failures here are non-fatal — the chips just stay hidden.
        if let history = try? await CheckInService.shared.checkInHistory(
            receiverId: session.user.id,
            familyId: family.id,
            days: 30
        ) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoTimestamps = history.map { isoFormatter.string(from: $0.checkedInAt) }
            // Use the receiver's configured timezone so the streak/consistency
            // chips bucket days the same way the status query does.
            let cal = receiverCalendar
            // A receiver with multiple windows/day must hit all of them for a
            // day to count toward the streak (US-IOS048). settings is loaded
            // above; default to 1/day if unavailable.
            let expectedPerDay = receiverSettings.map { Self.slotsCount(for: $0, calendar: cal) } ?? 1
            streakDays = Streaks.currentStreak(
                isoTimestamps: isoTimestamps, expectedPerDay: expectedPerDay, calendar: cal)
            consistencyPercent = Streaks.consistencyPercent(
                isoTimestamps: isoTimestamps, expectedPerDay: expectedPerDay, windowDays: 7, calendar: cal)
        }

        // (Re)schedule or clear the local fallback reminder safety net.
        await refreshLocalFallbackReminder()

        isOffline = !offlineService.isOnline
        pendingOfflineCount = offlineService.pendingCount

        // Publish a snapshot to the shared App Group so Siri, Shortcuts, the
        // widget, the Control Center control, and the watch can check in and
        // show today's status without a live app session. "Done" only when
        // nothing is owed, so the widget offers the button for a later request.
        await SharedCheckInPublisher.publish(
            familyId: family.id,
            isKidMode: receiverMode == .kid,
            hasCheckedInToday: hasCheckedInToday,
            lastCheckInAt: lastCheckIn?.checkedInAt,
            nextCheckInAt: nextCheckInTime,
            displayName: nil
        )
    }

    /// Offline fallback for `performLoadStatus`: the family and today's status
    /// from the snapshot this phone published on its last successful load.
    private func loadCachedStatus() {
        isOffline = !offlineService.isOnline
        pendingOfflineCount = offlineService.pendingCount
        guard let snapshot = SharedCheckInStore.load(),
              let cachedFamily = UUID(uuidString: snapshot.familyId),
              let cachedReceiver = UUID(uuidString: snapshot.receiverId) else { return }
        familyId = cachedFamily
        // Recomputed every time, never only set: this object outlives scene
        // phases, so an offline receiver who checked in yesterday must be
        // offered the button again after midnight.
        let queued = hasQueuedCheckInToday(familyId: cachedFamily, receiverId: cachedReceiver)
        let lastIsToday = lastCheckIn.map { receiverCalendar.isDateInToday($0.checkedInAt) } ?? false
        hasCheckedInToday = snapshot.isCheckedIn() || queued || lastIsToday
        if hasCheckedInToday { owesLaterAnswer = false }
        checkInSavedOffline = queued && !lastIsToday
        if hasCheckedInToday { clearStaleMessages() }
        if nextCheckInTime == nil || (nextCheckInTime ?? .distantPast) < Date() {
            nextCheckInTime = snapshot.nextCheckInAt
        }
    }

    /// Whether an unsynced check-in from today, for this receiver and family,
    /// is waiting in the offline queue.
    private func hasQueuedCheckInToday(familyId: UUID, receiverId: UUID) -> Bool {
        offlineService.hasUnsyncedCheckInToday(familyId: familyId, receiverId: receiverId)
    }

    /// A check-in has landed (here or elsewhere): an earlier failed tap's error
    /// and "Try Again", or a failed snooze's message, no longer apply.
    private func clearStaleMessages() {
        errorMessage = nil
        errorRecovery = .retry
        actionMessage = nil
    }

    /// The owner's name and phone. Receivers may read family members' users
    /// rows (00002 "Family members can read each other"). Best-effort.
    private func loadOwnerContact(ownerId: UUID) async {
        struct OwnerRow: Decodable {
            let displayName: String?
            let phone: String?
            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case phone
            }
        }
        guard let row: OwnerRow = try? await SupabaseService.shared.client
            .from("users")
            .select("display_name, phone")
            .eq("id", value: ownerId.uuidString)
            .single()
            .execute()
            .value else { return }
        ownerName = JoinPreview.presentableName(row.displayName)
        let phone = row.phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        ownerPhone = (phone?.isEmpty == false) ? phone : nil
    }

    /// Every pending request, newest first. `try?`: a failure leaves the
    /// banner off, as before.
    private func loadPendingRequests(receiverId: UUID, familyId: UUID) async -> [CheckInRequest] {
        let requests: [CheckInRequest]? = try? await SupabaseService.shared.client
            .from("checkin_requests")
            .select()
            .eq("receiver_id", value: receiverId.uuidString)
            .eq("family_id", value: familyId.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .limit(10)
            .execute()
            .value
        return requests ?? []
    }

    /// Banner, snooze and "reminded at" state from `pendingRequests`.
    private func applyPendingRequestState(now: Date = Date()) {
        // A caregiver's stand-down (00055/00058) leaves the request pending but
        // nobody is waiting on it any more.
        let live = pendingRequests.filter { $0.stoodDownAt == nil }
        let active = live.filter { Self.isActivelyPending($0, now: now) }
        hasPendingRequest = !hasCheckedInToday && !active.isEmpty
        let newest = active.first
        pendingRequestId = hasPendingRequest ? newest?.id : nil
        pendingRequestType = hasPendingRequest ? newest?.type : nil
        pendingRequestAskedAt = hasPendingRequest ? newest?.createdAt : nil
        let left = active.map { Self.maxSnoozes - ($0.snoozeCount ?? 0) }.min()
        snoozesLeft = hasPendingRequest ? left.map { max(0, $0) } : nil
        // Receiver can snooze while a request is actively pending and the server
        // cap hasn't been hit (nil count = older backend = allow).
        canSnooze = hasPendingRequest && (left ?? Self.maxSnoozes) > 0
        // Snoozed and nothing else is waiting: "We'll remind you at 3:45 PM".
        if hasCheckedInToday || !active.isEmpty {
            snoozedUntil = nil
        } else {
            snoozedUntil = live.compactMap(\.snoozedUntil).filter { $0 > now }.max()
        }
    }

    /// Whether a fetched pending request should be surfaced as *actively*
    /// pending. A request whose `snoozedUntil` is still in the future was just
    /// snoozed and must not re-surface the pending banner. Pure for testability.
    nonisolated static func isActivelyPending(_ request: CheckInRequest?, now: Date = Date()) -> Bool {
        guard let request else { return false }
        if let until = request.snoozedUntil, until > now { return false }
        return true
    }

    /// Snooze every actively pending request (usually one; an owner's "check
    /// on them now" can sit beside a scheduled one, and snoozing an arbitrary
    /// one of them left the other escalating), defer the local reminder to the
    /// snooze end, and say when that is.
    func snoozePendingRequest() async {
        guard hasPendingRequest, !isSnoozing else { return }
        isSnoozing = true
        actionMessage = nil
        noticeMessage = nil
        defer { isSnoozing = false }

        let targets = pendingRequests.filter { $0.stoodDownAt == nil && Self.isActivelyPending($0) }
        var latestUntil: Date?
        var firstError: Error?
        for request in targets {
            do {
                let updated = try await CheckInService.shared.snoozeCheckIn(
                    requestId: request.id, minutes: Self.snoozeMinutes
                )
                if let index = pendingRequests.firstIndex(where: { $0.id == updated.id }) {
                    pendingRequests[index] = updated
                }
                if let until = updated.snoozedUntil, until > (latestUntil ?? .distantPast) {
                    latestUntil = until
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let latestUntil {
            // The server moved the escalation to at least this time.
            hasPendingRequest = false
            canSnooze = false
            snoozedUntil = latestUntil
            await PushNotificationService.shared.scheduleLocalCheckinFallback(
                at: latestUntil,
                isKidMode: receiverMode == .kid
            )
            await AnalyticsService.shared.track(.checkInSnoozed)
            DailyOKHaptics.success()
            return
        }

        guard let firstError else { return }
        let outcome = Self.snoozeFailure(firstError)
        actionMessage = outcome.message
        if outcome.armFallback {
            // Couldn't reach the server: the family WILL be alerted on the
            // normal schedule, but the promised reminder still comes.
            await PushNotificationService.shared.scheduleLocalCheckinFallback(
                at: Date().addingTimeInterval(TimeInterval(Self.snoozeMinutes * 60)),
                isKidMode: receiverMode == .kid
            )
        }
        if outcome.reload { await loadStatus(force: true) }
    }

    /// Plain words for a failed snooze, and what to do next. Pure.
    nonisolated static func snoozeFailure(_ error: Error) -> (message: String, reload: Bool, armFallback: Bool) {
        let text = "\(error) \(error.localizedDescription)"
        if text.contains("Snooze limit reached") {
            return (String(localized: "You've snoozed \(maxSnoozes) times. Tap \"I'm OK\" when you can."), true, false)
        }
        if OfflineCheckInService.isConnectivityError(error) {
            return (String(localized: "Couldn't reach Daily OK, so your family may still be alerted. We'll remind you in \(snoozeMinutes) minutes."), false, true)
        }
        if text.contains("Only a pending check-in can be snoozed") || text.contains("Check-in request not found") {
            // Answered elsewhere (widget, watch) or stood down: nothing to snooze.
            return (String(localized: "There's nothing to snooze — your family isn't waiting on this one any more."), true, false)
        }
        return (String(localized: "Couldn't snooze right now. Tap \"I'm OK\" when you can."), true, false)
    }

    /// Schedule a one-shot local reminder as a safety net against a missed
    /// server push: at the end of a snooze, else for the next window nobody
    /// has answered yet (plus grace).
    private func refreshLocalFallbackReminder() async {
        if let until = snoozedUntil, until > Date() {
            // The snooze promised "remind me in 15 min". The routine refresh used
            // to replace that reminder with tomorrow's on every foreground.
            await PushNotificationService.shared.scheduleLocalCheckinFallback(
                at: until,
                isKidMode: receiverMode == .kid
            )
            return
        }
        guard let settings = receiverSettings, !settings.schedulePaused,
              let fallbackDate = nextFallbackDate(from: settings) else {
            await PushNotificationService.shared.cancelLocalCheckinFallback()
            return
        }
        await PushNotificationService.shared.scheduleLocalCheckinFallback(
            at: fallbackDate,
            isKidMode: receiverMode == .kid
        )
    }

    /// Next window nobody has answered (today if still upcoming, else a later
    /// day), pushed out by the grace period so the local fallback fires only
    /// after the server push has had its chance.
    private func nextFallbackDate(from settings: ReceiverSettings) -> Date? {
        let cal = receiverCalendar
        guard let target = Self.nextUnansweredCheckIn(
            for: settings, todayCheckIns: todayCheckIns, now: nextCheckInReference(), calendar: cal
        ) else { return nil }
        return cal.date(byAdding: .minute, value: settings.gracePeriodMinutes, to: target)
    }

    /// Whether a receiver who already checked in today owes another answer:
    /// a request raised after their last check-in (an owner's "check on them
    /// now", a later window's reminder), or — on a multi-window day — the
    /// current window is unanswered and due within `leadMinutes`. Pure.
    nonisolated static func owesAnotherAnswer(
        todayCheckIns: [CheckIn],
        pendingRequests: [CheckInRequest],
        settings: ReceiverSettings?,
        now: Date = Date(),
        calendar: Calendar = .current,
        leadMinutes: Int = nextWindowLeadMinutes
    ) -> Bool {
        guard let latest = todayCheckIns.map(\.checkedInAt).max() else { return false }
        if pendingRequests.contains(where: {
            $0.status == .pending && $0.stoodDownAt == nil && $0.createdAt > latest
        }) {
            return true
        }
        guard let settings, !settings.schedulePaused,
              scheduledTimes(for: settings, on: now, calendar: calendar).count > 1,
              let current = currentSlotKey(for: settings, now: now, calendar: calendar),
              let (hour, minute) = parseCheckinTime(current) else { return false }
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let windowTime = calendar.date(from: comps),
              windowTime.timeIntervalSince(now) <= TimeInterval(leadMinutes * 60) else { return false }
        return !isSlotAnswered(current, todayCheckIns: todayCheckIns, settings: settings, calendar: calendar)
    }

    /// Whether today's rows answer window `slot`. A row carries its slot_key;
    /// a day-level row (no slot: the widget, an older build) answers the
    /// window nearest to when it was made — the same rule a tap is tagged by.
    nonisolated static func isSlotAnswered(
        _ slot: String,
        todayCheckIns: [CheckIn],
        settings: ReceiverSettings,
        calendar: Calendar
    ) -> Bool {
        todayCheckIns.contains { row in
            if let key = row.slotKey { return key == slot }
            return currentSlotKey(for: settings, now: row.checkedInAt, calendar: calendar) == slot
        }
    }

    /// The next scheduled check-in nobody has answered yet. A single-window
    /// day is answered by any row today; a multi-window day window by window.
    /// "Next check-in: Today at 8:00 AM" used to show after a 7:00 check-in
    /// that already covered it. Pure.
    nonisolated static func nextUnansweredCheckIn(
        for settings: ReceiverSettings,
        todayCheckIns: [CheckIn],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        var cursor = now
        for _ in 0..<12 {
            guard let candidate = nextScheduledCheckIn(for: settings, now: cursor, calendar: calendar) else { return nil }
            guard calendar.isDate(candidate, inSameDayAs: now), !todayCheckIns.isEmpty else { return candidate }
            let answered: Bool
            if scheduledTimes(for: settings, on: now, calendar: calendar).count > 1,
               let slot = currentSlotKey(for: settings, now: candidate, calendar: calendar) {
                answered = isSlotAnswered(slot, todayCheckIns: todayCheckIns, settings: settings, calendar: calendar)
            } else {
                answered = true
            }
            if !answered { return candidate }
            cursor = candidate.addingTimeInterval(60)
        }
        return nil
    }

    /// Parse a stored "HH:mm[:ss]" check-in time into hour/minute components.
    nonisolated static func parseCheckinTime(_ raw: String) -> (hour: Int, minute: Int)? {
        let parts = raw.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// Resolve the next scheduled check-in moment, honoring the full schedule
    /// model: `scheduleType` (daily / weekday-weekend / custom), weekend and
    /// per-day custom times, `schedulePaused`, and quiet hours. Returns nil when
    /// paused or no day in the coming week has a scheduled time. Pure + testable.
    nonisolated static func nextScheduledCheckIn(
        for settings: ReceiverSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard !settings.schedulePaused else { return nil }

        // Scan today + a full week for the earliest scheduled slot after `now`.
        // A custom day may have multiple windows (US-IOS048), so consider every
        // time scheduled that day, in order.
        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            for timeString in scheduledTimes(for: settings, on: day, calendar: calendar) {
                guard let (hour, minute) = parseCheckinTime(timeString) else { continue }

                var comps = calendar.dateComponents([.year, .month, .day], from: day)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0
                guard let rawTarget = calendar.date(from: comps) else { continue }

                let target = deferPastQuietHours(rawTarget, settings: settings, calendar: calendar)
                if target > now { return target }
            }
        }
        return nil
    }

    /// The day-of-week key ("mon".."sun") for a date.
    nonisolated private static func dayKey(for day: Date, calendar: Calendar) -> String {
        switch calendar.component(.weekday, from: day) {
        case 1: return "sun"
        case 2: return "mon"
        case 3: return "tue"
        case 4: return "wed"
        case 5: return "thu"
        case 6: return "fri"
        case 7: return "sat"
        default: return "mon"
        }
    }

    /// All "HH:mm" times scheduled for the given day, sorted ascending. Empty if
    /// no check-in is scheduled that day. For daily/weekday-weekend schedules
    /// this is a single time; custom schedules may return several (US-IOS048).
    nonisolated static func scheduledTimes(
        for settings: ReceiverSettings,
        on day: Date,
        calendar: Calendar
    ) -> [String] {
        let weekday = calendar.component(.weekday, from: day) // 1 = Sun ... 7 = Sat
        let isWeekend = (weekday == 1 || weekday == 7)

        switch settings.scheduleType {
        case .daily:
            return [settings.checkinTime]
        case .weekdayWeekend:
            return [isWeekend ? (settings.weekendCheckinTime ?? settings.checkinTime) : settings.checkinTime]
        case .custom:
            guard let custom = settings.customSchedule else { return [settings.checkinTime] }
            return custom.times(forDayKey: dayKey(for: day, calendar: calendar))
        }
    }

    /// Number of check-in windows scheduled for `day` — the "expected per day"
    /// count used by streak/consistency math (US-IOS048).
    nonisolated static func slotsCount(
        for settings: ReceiverSettings,
        on day: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        max(1, scheduledTimes(for: settings, on: day, calendar: calendar).count)
    }

    /// The slot key to attach to a check-in happening at `now`. Returns nil when
    /// the day has at most one window (legacy day-level dedup is preserved).
    /// Otherwise returns the "HH:mm" of the window this check-in is responding
    /// to — the scheduled time closest to `now` — so multiple windows in a day
    /// stay distinct server-side.
    nonisolated static func currentSlotKey(
        for settings: ReceiverSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        let times = scheduledTimes(for: settings, on: now, calendar: calendar)
        guard times.count > 1 else { return nil }

        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var best: (time: String, distance: Int)?
        for time in times {
            guard let (h, m) = parseCheckinTime(time) else { continue }
            let distance = abs(h * 60 + m - nowMinutes)
            if best == nil || distance < best!.distance {
                best = (time, distance)
            }
        }
        return best?.time
    }

    /// If `date` falls inside the receiver's quiet hours, defer it to the end of
    /// quiet hours so a reminder isn't scheduled during a do-not-disturb window.
    nonisolated private static func deferPastQuietHours(
        _ date: Date,
        settings: ReceiverSettings,
        calendar: Calendar
    ) -> Date {
        guard let qStart = settings.quietHoursStart, let qEnd = settings.quietHoursEnd,
              let (sh, sm) = parseCheckinTime(qStart), let (eh, em) = parseCheckinTime(qEnd) else {
            return date
        }
        let minutesOfDay = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let startMin = sh * 60 + sm
        let endMin = eh * 60 + em

        let inQuiet: Bool
        if startMin <= endMin {
            inQuiet = minutesOfDay >= startMin && minutesOfDay < endMin
        } else {
            // Window wraps midnight (e.g. 22:00–07:00).
            inQuiet = minutesOfDay >= startMin || minutesOfDay < endMin
        }
        guard inQuiet else { return date }

        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = eh
        comps.minute = em
        comps.second = 0
        var endDate = calendar.date(from: comps) ?? date
        if endDate <= date {
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        return endDate
    }

    private func loadReceiverSettings(userId: UUID, familyId: UUID) async {
        do {
            let members: [FamilyMember] = try await SupabaseService.shared.client
                .from("family_members")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("family_id", value: familyId.uuidString)
                .limit(1)
                .execute()
                .value

            guard let member = members.first else { return }
            receiverMemberId = member.id

            let settings: ReceiverSettings = try await SupabaseService.shared.client
                .from("receiver_settings")
                .select()
                .eq("family_member_id", value: member.id.uuidString)
                .single()
                .execute()
                .value

            receiverSettings = settings
            receiverMode = settings.receiverMode
            simpleMode = settings.simpleMode
            audioConfirmationEnabled = settings.audioConfirmationEnabled
            computeNextCheckInTime(from: settings)
        } catch {
            // Non-critical — default to standard mode
        }
    }

    /// Receiver self-service: toggle Simple Mode from their own device.
    func updateSimpleMode(_ value: Bool) async {
        let previous = simpleMode
        simpleMode = value
        if !(await saveDisplayPrefs(simpleMode: value)) { simpleMode = previous }
    }

    /// Receiver self-service: toggle spoken/audible confirmation.
    func updateAudioConfirmation(_ value: Bool) async {
        let previous = audioConfirmationEnabled
        audioConfirmationEnabled = value
        if !(await saveDisplayPrefs(audioConfirmation: value)) { audioConfirmationEnabled = previous }
    }

    /// Save through set_my_receiver_display_prefs (00061) and adopt what the
    /// server stored. The old direct PATCH matched 0 rows under RLS (receivers
    /// may only read receiver_settings), answered 204, played the success
    /// haptic, and the next load put the old value back — every time. Success
    /// is now only what the server confirms.
    private func saveDisplayPrefs(simpleMode newSimple: Bool? = nil, audioConfirmation newAudio: Bool? = nil) async -> Bool {
        actionMessage = nil
        guard let familyId else {
            actionMessage = String(localized: "Couldn't save that setting yet. Try again in a moment.")
            return false
        }
        do {
            let stored = try await CheckInService.shared.setMyDisplayPrefs(
                familyId: familyId, simpleMode: newSimple, audioConfirmation: newAudio
            )
            simpleMode = stored.simpleMode
            audioConfirmationEnabled = stored.audioConfirmationEnabled
            receiverSettings?.simpleMode = stored.simpleMode
            receiverSettings?.audioConfirmationEnabled = stored.audioConfirmationEnabled
            let confirmed = (newSimple.map { $0 == stored.simpleMode } ?? true)
                && (newAudio.map { $0 == stored.audioConfirmationEnabled } ?? true)
            if confirmed { DailyOKHaptics.success() }
            return confirmed
        } catch {
            Log.settings.error("Failed to save receiver display prefs: \(error.localizedDescription, privacy: .public)")
            actionMessage = OfflineCheckInService.isConnectivityError(error)
                ? String(localized: "Couldn't save that setting — you're offline. Try again when you're connected.")
                : String(localized: "Couldn't save that setting. Please try again later.")
            DailyOKHaptics.error()
            return false
        }
    }

    private func computeNextCheckInTime(from settings: ReceiverSettings) {
        // The next window nobody has answered, in the receiver's account zone
        // (nil when paused). After a 7:00 check-in for the 8:00 window it says
        // tomorrow, not "Today at 8:00 AM".
        nextCheckInTime = Self.nextUnansweredCheckIn(
            for: settings,
            todayCheckIns: todayCheckIns,
            now: nextCheckInReference(),
            calendar: receiverCalendar
        )
    }

    /// Where to start looking for the next check-in. A check-in queued on this
    /// phone isn't in `todayCheckIns` yet but does answer today's window.
    private func nextCheckInReference() -> Date {
        let cal = receiverCalendar
        guard checkInSavedOffline, todayCheckIns.isEmpty,
              let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) else { return Date() }
        return cal.startOfDay(for: tomorrow)
    }

    func performCheckIn() async {
        guard let familyId, !isCheckingIn else { return }

        isCheckingIn = true
        errorMessage = nil
        errorRecovery = .retry
        noticeMessage = nil

        // Tag the check-in with the window it satisfies so a receiver with
        // multiple windows/day (US-IOS048) doesn't collapse to one row. nil for
        // single-window receivers preserves legacy one-per-day dedup. In the
        // receiver's account zone, like dispatch — not the device zone.
        let slotKey = receiverSettings.flatMap { Self.currentSlotKey(for: $0, calendar: receiverCalendar) }

        do {
            let checkIn = try await offlineService.performCheckIn(
                familyId: familyId,
                mood: nil,
                source: .app,
                slotKey: slotKey
            )

            hasCheckedInToday = true
            owesLaterAnswer = false
            hasPendingRequest = false
            snoozedUntil = nil
            selectedMood = nil
            actionMessage = nil
            if let checkIn {
                lastCheckIn = checkIn
                checkInSavedOffline = false
                savedBecauseServerBusy = false
                // Undo only a row this tap created. Answering an owner's later
                // request returns the morning row (day-level dedup); undoing
                // that would delete the morning check-in.
                if !checkIn.isHelpSignal,
                   Date().timeIntervalSince(checkIn.checkedInAt) < Self.undoGraceSeconds {
                    startUndoWindow()
                } else {
                    undoableUntil = nil
                }
                Task { await AnalyticsService.shared.track(.checkIn) }
            } else {
                // Offline: saved on the phone, sent when back online. Not an
                // error, not "family notified", and nothing to undo yet.
                markSavedOffline(serverBusy: false)
            }
            await ReceiverCheckInAftermath.record(at: checkIn?.checkedInAt ?? Date())
        } catch let error as NetworkError {
            // Queued: no connectivity, or the server unreachable behind its proxy.
            hasCheckedInToday = true
            owesLaterAnswer = false
            hasPendingRequest = false
            if case .serverUnavailable = error {
                markSavedOffline(serverBusy: true)
                scheduleQueueRetry()
            } else {
                markSavedOffline(serverBusy: false)
            }
            await ReceiverCheckInAftermath.record(at: Date())
        } catch {
            // Real failure (auth, server refusal): do NOT flip the UI to
            // "checked in" — otherwise the receiver sees "you're all set"
            // for a check-in that was never recorded. Plain words, not
            // "Edge function error 500: {json}".
            let failure = Self.checkInFailure(error, ownerName: ownerName)
            errorMessage = failure.message
            errorRecovery = failure.recovery
        }

        isCheckingIn = false
    }

    private func markSavedOffline(serverBusy: Bool) {
        checkInSavedOffline = true
        savedBecauseServerBusy = serverBusy
        if !serverBusy { isOffline = true }
        undoableUntil = nil
        pendingOfflineCount = offlineService.pendingCount
        Task { await AnalyticsService.shared.track(.checkInOffline) }
    }

    /// The phone is online but the server wasn't answering: try the queue
    /// again in a minute rather than waiting for the next foreground.
    private func scheduleQueueRetry() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            guard let self else { return }
            await self.offlineService.syncPendingCheckIns()
        }
    }

    /// Plain words for a failed check-in, and what the screen should offer.
    /// Pure for testability.
    nonisolated static func checkInFailure(_ error: Error, ownerName: String?) -> (message: String, recovery: CheckInRecovery) {
        let family = ownerName ?? String(localized: "your family")
        var underlying = error
        if let appError = error as? DailyOKError {
            switch appError {
            case .network(let inner), .unknown(let inner): underlying = inner
            default: break
            }
        }
        if let checkInError = underlying as? CheckInError, case .notAuthenticated = checkInError {
            return (String(localized: "You've been signed out on this phone. Sign in again to check in."), .signIn)
        }
        if let queueError = underlying as? OfflineCheckInService.OfflineQueueError {
            return (queueError.localizedDescription, .retry)
        }
        if let http = underlying as? EdgeFunctionsClient.HTTPError {
            switch http.status {
            case 401:
                return (String(localized: "You've been signed out on this phone. Sign in again to check in."), .signIn)
            case 403:
                return (String(localized: "You're no longer part of this family's check-ins. Ask \(family) to invite you again."), .none)
            case 426:
                return (String(localized: "Please update Daily OK to keep checking in."), .none)
            default:
                return (String(localized: "Couldn't reach Daily OK. Try again in a minute, or call \(family)."), .retry)
            }
        }
        if OfflineCheckInService.isConnectivityError(underlying) {
            return (String(localized: "Couldn't reach Daily OK. Try again in a minute, or call \(family)."), .retry)
        }
        return (String(localized: "Something went wrong. Try again, or call \(family)."), .retry)
    }

    // MARK: - Help, call me, kid replies

    /// Send a help request, call-me, SOS or kid reply. Live only — an urgent
    /// signal is never queued for silent later delivery (same rule as the
    /// notification actions). Attaches battery and, if location access is
    /// already allowed, an approximate location (bounded wait).
    func sendHelp(_ kind: ReceiverHelpKind) async {
        guard let familyId, !isSendingHelp else { return }
        isSendingHelp = true
        helpFailure = nil
        noticeMessage = nil
        defer { isSendingHelp = false }

        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let battery: Double? = level >= 0 ? Double(level) : nil
        let location = await Self.quickLocation(within: 4)

        do {
            let row = try await NetworkRetry.execute(maxAttempts: 2) {
                try await CheckInService.shared.checkIn(
                    familyId: familyId,
                    source: .app,
                    responseType: kind.responseType,
                    location: location,
                    batteryLevel: battery,
                    kidResponseType: kind.kidResponseType?.rawValue
                )
            }
            lastCheckIn = row
            if kind.isUrgent {
                helpStatus = HelpStatus(kind: kind, sentAt: Date(), acknowledgedBy: nil, acknowledgedAt: nil)
                // A help row is not undoable.
                undoableUntil = nil
                DailyOKHaptics.warning()
            } else {
                noticeMessage = kind.sentMessage(owner: ownerName)
                DailyOKHaptics.success()
            }
            await ReceiverCheckInAftermath.record(at: row.checkedInAt)
        } catch {
            helpFailure = HelpFailure(kind: kind, message: Self.helpFailureMessage(error, ownerName: ownerName))
            DailyOKHaptics.error()
        }
    }

    /// "Didn't send" copy for a help request. Pure.
    nonisolated static func helpFailureMessage(_ error: Error, ownerName: String?) -> String {
        let family = ownerName ?? String(localized: "your family")
        if OfflineCheckInService.isConnectivityError(error) {
            return String(localized: "Not sent — your phone is offline. Call \(family) instead.")
        }
        return String(localized: "Not sent — Daily OK couldn't be reached. Call \(family) instead.")
    }

    /// The open help request and who has taken it on (00061). Falls back to
    /// today's row when the server predates the function.
    private func refreshHelpStatus(familyId: UUID) async {
        let rowKind = lastCheckIn.flatMap(ReceiverHelpKind.from(checkIn:))
        guard rowKind != nil || helpStatus != nil else {
            helpStatus = nil
            return
        }
        do {
            let open = try await CheckInService.shared.myOpenHelpRequest(familyId: familyId)
            helpStatus = Self.deriveHelpStatus(open: open, rowKind: rowKind, rpcAvailable: true)
        } catch {
            helpStatus = Self.deriveHelpStatus(open: nil, rowKind: rowKind, rpcAvailable: false)
        }
    }

    /// Pure: the help card's state.
    nonisolated static func deriveHelpStatus(open: OpenHelpRequest?, rowKind: ReceiverHelpKind?, rpcAvailable: Bool) -> HelpStatus? {
        if let open, let type = open.type, type == "need_help" || type == "call_me" {
            let kind: ReceiverHelpKind = rowKind == .sos ? .sos : (type == "call_me" ? .callMe : .needHelp)
            let who = open.acknowledgedByName.flatMap { JoinPreview.presentableName($0) }
            return HelpStatus(kind: kind, sentAt: open.createdAt, acknowledgedBy: who, acknowledgedAt: open.acknowledgedAt)
        }
        if !rpcAvailable, let rowKind {
            return HelpStatus(kind: rowKind, sentAt: nil, acknowledgedBy: nil, acknowledgedAt: nil)
        }
        return nil
    }

    /// Current location if access is already allowed, waiting at most
    /// `seconds`. Never prompts; never blocks a help request on a slow fix.
    static func quickLocation(within seconds: Double) async -> CheckInLocation? {
        let status = LocationService.shared.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        return await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            Task { gate.resume(await LocationService.shared.getCurrentLocation()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                gate.resume(nil)
            }
        }
    }

    // MARK: - Undo

    /// Open the post-check-in undo window and auto-close it when the grace
    /// period lapses so the button can't linger past the server-side limit.
    private func startUndoWindow() {
        openUndoWindow(deadline: Date().addingTimeInterval(Self.undoGraceSeconds))
    }

    /// Open (or re-open) the undo window to a specific deadline and schedule it to
    /// auto-close. Used both right after a check-in and when a reload finds the
    /// grace window still open, so the Undo button survives backgrounding.
    private func openUndoWindow(deadline: Date) {
        undoableUntil = deadline
        Task { [weak self] in
            let interval = deadline.timeIntervalSinceNow
            if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
            guard let self else { return }
            // Only clear if it's still the same window we opened (a later
            // check-in may have re-opened it).
            if self.undoableUntil == deadline { self.undoableUntil = nil }
        }
    }

    /// Undo the just-recorded check-in (US-IOS048). Reverses the server row,
    /// re-opens any requests it closed, and returns the UI to the pre-check-in
    /// state. No-op once the grace window has lapsed, and never for a help
    /// request (it has already paged the family).
    func undoCheckIn() async {
        guard let familyId, let until = undoableUntil, until > Date(), !isUndoing,
              lastCheckIn?.isHelpSignal != true else { return }
        isUndoing = true
        actionMessage = nil
        defer { isUndoing = false }
        do {
            try await CheckInService.shared.undoLastCheckIn(familyId: familyId)
            // Roll the UI back to "not yet checked in".
            hasCheckedInToday = false
            lastCheckIn = nil
            todayCheckIns = []
            selectedMood = nil
            undoableUntil = nil
            noticeMessage = String(localized: "Check-in undone. Tap \"I'm OK\" when you're ready.")
            // Not `clear()`: that also wiped the shared session tokens and
            // signed the widget, Siri and the watch out.
            SharedCheckInPublisher.markNotCheckedIn()
            // Re-evaluate the pending request and fallback reminder with a load
            // that starts after the undo.
            await loadStatus(force: true)
            DailyOKHaptics.warning()
            Task { await AnalyticsService.shared.track(.checkInUndone) }
        } catch {
            let failure = Self.undoFailure(error, ownerName: ownerName)
            actionMessage = failure.message
            if failure.windowClosed { undoableUntil = nil }
        }
    }

    /// Plain words for a failed undo. Pure.
    nonisolated static func undoFailure(_ error: Error, ownerName: String?) -> (message: String, windowClosed: Bool) {
        let family = ownerName ?? String(localized: "your family")
        if let http = error as? EdgeFunctionsClient.HTTPError {
            let code = http.serverMessage ?? ""
            if code == "urgent_not_undoable" {
                return (String(localized: "A help request can't be undone. If you're OK, call \(family) to let them know."), true)
            }
            if http.status == 409 || code == "undo_window_expired" {
                return (String(localized: "It's too late to undo. \(family.capitalizedFirst) already has this check-in."), true)
            }
            if http.status == 404 {
                return (String(localized: "There's no check-in to undo."), true)
            }
        }
        if OfflineCheckInService.isConnectivityError(error) {
            return (String(localized: "Couldn't undo — you're offline. Your check-in still counts."), false)
        }
        return (String(localized: "Couldn't undo right now. Your check-in still counts."), false)
    }

    /// Attach an optional mood to today's check-in row after the fact. Updates
    /// the UI optimistically; a failure is non-fatal (the check-in itself stands).
    func setMood(_ mood: Mood) async {
        selectedMood = mood
        guard let checkIn = lastCheckIn else { return }
        do {
            try await SupabaseService.shared.client
                .from("checkins")
                .update(["mood": mood.rawValue])
                .eq("id", value: checkIn.id.uuidString)
                .execute()
            await AnalyticsService.shared.track(.moodSubmitted, properties: ["mood": mood.rawValue])
        } catch {
            // Non-fatal — keep the optimistic selection; the row just lacks a mood.
        }
    }
}

/// Resumes a continuation exactly once, whichever racer finishes first.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

private extension String {
    /// "your family" → "Your family"; names unchanged.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
