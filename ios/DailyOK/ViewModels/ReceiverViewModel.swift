import SwiftUI
import os
import Supabase

@MainActor
final class ReceiverViewModel: ObservableObject {
    @Published var hasCheckedInToday = false
    @Published var isCheckingIn = false
    @Published var lastCheckIn: CheckIn?
    @Published var errorMessage: String?
    @Published var familyId: UUID?
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
    /// True when the family is actively waiting on a response (a pending
    /// checkin_request exists) and the receiver hasn't checked in yet.
    @Published var hasPendingRequest = false
    /// The pending request's id (for snoozing), and whether the receiver can
    /// still snooze it (server caps the count at 3).
    @Published var pendingRequestId: UUID?
    @Published var canSnooze = false
    @Published var isSnoozing = false
    /// Set after a successful snooze so the UI can confirm ("Snoozed for 15 min").
    @Published var snoozeConfirmation: String?
    /// Mood the receiver picked after checking in (optional, post-check-in).
    @Published var selectedMood: Mood?
    /// While set (and in the future), the just-recorded check-in can still be
    /// undone (US-IOS048). Cleared when the grace window lapses or undo runs.
    @Published var undoableUntil: Date?
    /// True while an undo network call is in flight.
    @Published var isUndoing = false

    /// Minutes a snooze defers the request, and the server-side snooze cap.
    static let snoozeMinutes = 15
    private static let maxSnoozes = 3

    /// How long after checking in the receiver may undo an accidental tap.
    /// Kept just under the server-side grace so an in-window tap won't 409.
    static let undoGraceSeconds: TimeInterval = 150

    private let offlineService = OfflineCheckInService.shared
    private var loadTask: Task<Void, Never>?
    /// The receiver's own family_member id, so they can self-serve display
    /// preferences (Simple Mode, spoken confirmation) without an owner.
    private var receiverMemberId: UUID?

    /// Whether to show the optional "how are you feeling?" picker after a
    /// check-in: enabled in settings, an online check-in row exists to attach to,
    /// and no mood has been recorded yet.
    var shouldPromptForMood: Bool {
        guard receiverSettings?.moodTrackingEnabled == true else { return false }
        guard let checkIn = lastCheckIn, checkIn.mood == nil else { return false }
        return selectedMood == nil
    }

    /// Coalesce reload triggers. `loadStatus` is invoked from `.task`,
    /// `scenePhase == .active`, AND the `didSyncCheckIns` observer — and
    /// `loadStatus` itself calls `syncPendingCheckIns()`, which on success posts
    /// `didSyncCheckIns`. Without coalescing, that re-enters `loadStatus` for a
    /// full extra round of queries. Re-entrant callers await the in-flight load.
    func loadStatus() async {
        if let loadTask {
            return await loadTask.value
        }
        let task = Task { await performLoadStatus() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoadStatus() async {
        guard let family = try? await FamilyService.shared.getFamily() else { return }
        familyId = family.id

        guard let session = try? await SupabaseService.shared.client.auth.session else { return }

        struct TimezoneOnly: Decodable { let timezone: String? }
        let tzRow: TimezoneOnly? = try? await SupabaseService.shared.client
            .from("users")
            .select("timezone")
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value

        // Sync any queued offline check-ins first so the subsequent status
        // query reflects them. Without this, a synced check-in would only
        // appear after the next manual refresh.
        await offlineService.syncPendingCheckIns()

        // Reset state BEFORE the query so a stale `true` from yesterday
        // doesn't bleed into today if the query returns nil. The `@StateObject`
        // persists across scene phases, so without this reset the receiver
        // sees "you're all set" indefinitely once they check in once.
        let todayCheckIn = try? await CheckInService.shared.todayCheckInStatus(
            receiverId: session.user.id,
            familyId: family.id,
            timezone: tzRow?.timezone
        )
        Log.receiver.debug("loadStatus tz=\(tzRow?.timezone ?? "nil", privacy: .public) hasCheckedInToday=\(todayCheckIn != nil, privacy: .public)")
        lastCheckIn = todayCheckIn
        hasCheckedInToday = (todayCheckIn != nil)
        // A fresh load reflects server truth — clear any locally-picked mood so
        // the prompt reappears only if today's row genuinely has no mood yet.
        selectedMood = todayCheckIn?.mood

        await loadReceiverSettings(userId: session.user.id, familyId: family.id)

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
            // chips bucket days the same way `todayCheckInStatus` does.
            let cal = Calendar.forTimezone(tzRow?.timezone)
            // A receiver with multiple windows/day must hit all of them for a
            // day to count toward the streak (US-IOS048). settings is loaded
            // above; default to 1/day if unavailable.
            let expectedPerDay = receiverSettings.map { Self.slotsCount(for: $0, calendar: cal) } ?? 1
            streakDays = Streaks.currentStreak(
                isoTimestamps: isoTimestamps, expectedPerDay: expectedPerDay, calendar: cal)
            consistencyPercent = Streaks.consistencyPercent(
                isoTimestamps: isoTimestamps, expectedPerDay: expectedPerDay, windowDays: 7, calendar: cal)
        }

        // Surface whether the family is currently waiting on a response, but only
        // when the receiver hasn't already checked in today.
        if hasCheckedInToday {
            hasPendingRequest = false
        } else {
            await loadPendingRequest(receiverId: session.user.id, familyId: family.id)
        }

        // (Re)schedule or clear the local fallback reminder safety net.
        await refreshLocalFallbackReminder()

        isOffline = !offlineService.isOnline
        pendingOfflineCount = offlineService.pendingCount

        // Publish a snapshot to the shared App Group so Siri, Shortcuts, the
        // widget, the Control Center control, and the watch can check in and
        // show today's status without a live app session.
        await SharedCheckInPublisher.publish(
            familyId: family.id,
            isKidMode: receiverMode == .kid,
            hasCheckedInToday: hasCheckedInToday,
            lastCheckInAt: lastCheckIn?.checkedInAt,
            nextCheckInAt: nextCheckInTime,
            displayName: nil
        )
    }

    private func loadPendingRequest(receiverId: UUID, familyId: UUID) async {
        let requests: [CheckInRequest]? = try? await SupabaseService.shared.client
            .from("checkin_requests")
            .select()
            .eq("receiver_id", value: receiverId.uuidString)
            .eq("family_id", value: familyId.uuidString)
            .eq("status", value: "pending")
            .limit(1)
            .execute()
            .value
        let pending = requests?.first
        hasPendingRequest = pending != nil
        pendingRequestId = pending?.id
        // Receiver can snooze while a request is pending and the server cap
        // hasn't been hit (nil count = older backend = allow).
        canSnooze = pending != nil && (pending?.snoozeCount ?? 0) < Self.maxSnoozes
    }

    /// Snooze the pending request: defer escalation server-side and re-arm the
    /// local fallback reminder for `snoozeMinutes` from now. Best-effort — if the
    /// network call fails, the local reminder still fires and the server
    /// escalation proceeds normally (snooze is a deferral, not a guarantee).
    func snoozePendingRequest() async {
        guard let requestId = pendingRequestId, !isSnoozing else { return }
        isSnoozing = true
        snoozeConfirmation = nil
        defer { isSnoozing = false }

        do {
            let updated = try await CheckInService.shared.snoozeCheckIn(
                requestId: requestId, minutes: Self.snoozeMinutes
            )
            canSnooze = (updated.snoozeCount ?? Self.maxSnoozes) < Self.maxSnoozes
            snoozeConfirmation = "Snoozed for \(Self.snoozeMinutes) minutes."
            await PushNotificationService.shared.scheduleLocalCheckinFallback(
                at: Date().addingTimeInterval(TimeInterval(Self.snoozeMinutes * 60)),
                isKidMode: receiverMode == .kid
            )
            await AnalyticsService.shared.track(.checkInSnoozed)
        } catch {
            // Surface the most useful message (e.g. snooze limit reached) but
            // still defer the local reminder so the receiver isn't nagged early.
            errorMessage = (error as NSError).localizedDescription
            await PushNotificationService.shared.scheduleLocalCheckinFallback(
                at: Date().addingTimeInterval(TimeInterval(Self.snoozeMinutes * 60)),
                isKidMode: receiverMode == .kid
            )
        }
    }

    /// Schedule a one-shot local reminder as a safety net against a missed
    /// server push, or cancel it if the receiver has already checked in.
    private func refreshLocalFallbackReminder() async {
        guard !hasCheckedInToday, let settings = receiverSettings, !settings.schedulePaused,
              let fallbackDate = nextFallbackDate(from: settings) else {
            await PushNotificationService.shared.cancelLocalCheckinFallback()
            return
        }
        await PushNotificationService.shared.scheduleLocalCheckinFallback(
            at: fallbackDate,
            isKidMode: receiverMode == .kid
        )
    }

    /// Next moment a check-in is expected (today if still upcoming, else
    /// tomorrow), pushed out by the grace period so the local fallback fires
    /// only after the server push has had its chance.
    private func nextFallbackDate(from settings: ReceiverSettings) -> Date? {
        // Honor the full schedule (weekday/weekend/custom/paused/quiet-hours),
        // then push out by the grace period so the local fallback fires only
        // after the server push has had its chance.
        guard let target = Self.nextScheduledCheckIn(for: settings) else { return nil }
        return Calendar.current.date(byAdding: .minute, value: settings.gracePeriodMinutes, to: target)
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
        simpleMode = value
        await updateReceiverSetting(["simple_mode": String(value)])
    }

    /// Receiver self-service: toggle spoken/audible confirmation.
    func updateAudioConfirmation(_ value: Bool) async {
        audioConfirmationEnabled = value
        await updateReceiverSetting(["audio_confirmation_enabled": String(value)])
    }

    private func updateReceiverSetting(_ updates: [String: String]) async {
        guard let memberId = receiverMemberId else { return }
        do {
            try await SupabaseService.shared.client
                .from("receiver_settings")
                .update(updates)
                .eq("family_member_id", value: memberId.uuidString)
                .execute()
            DailyOKHaptics.success()
        } catch {
            Log.settings.error("Failed to update receiver setting: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func computeNextCheckInTime(from settings: ReceiverSettings) {
        // Use the full schedule resolver so the displayed "next check-in" matches
        // the receiver's weekday/weekend/custom schedule (and is nil when paused).
        nextCheckInTime = Self.nextScheduledCheckIn(for: settings)
    }

    func performCheckIn() async {
        guard let familyId, !isCheckingIn else { return }

        isCheckingIn = true
        errorMessage = nil

        // Tag the check-in with the window it satisfies so a receiver with
        // multiple windows/day (US-IOS048) doesn't collapse to one row. nil for
        // single-window receivers preserves legacy one-per-day dedup.
        let slotKey = receiverSettings.flatMap { Self.currentSlotKey(for: $0) }

        do {
            let checkIn = try await offlineService.performCheckIn(
                familyId: familyId,
                mood: nil,
                source: .app,
                slotKey: slotKey
            )

            if let checkIn {
                lastCheckIn = checkIn
            }
            hasCheckedInToday = true
            hasPendingRequest = false
            selectedMood = nil
            // Open the undo grace window for an accidental tap. Only for an
            // online check-in — an offline-queued one has no server row to undo.
            startUndoWindow()
            // Keep the shared snapshot (widget/Siri/watch) in sync immediately.
            SharedCheckInPublisher.markCheckedIn(at: checkIn?.checkedInAt ?? Date())
            // The server push did its job (or wasn't needed) — drop the local
            // safety-net reminder so it can't fire after a successful check-in.
            await PushNotificationService.shared.cancelLocalCheckinFallback()
            Task { await AnalyticsService.shared.track(.checkIn) }
        } catch let error as NetworkError {
            // Offline path: the check-in is queued locally and will sync when
            // connectivity returns. Show the success state optimistically.
            hasCheckedInToday = true
            isOffline = true
            Task { await AnalyticsService.shared.track(.checkInOffline) }
            pendingOfflineCount = offlineService.pendingCount
            errorMessage = error.localizedDescription
        } catch {
            // Real failure (auth, server 5xx, etc): do NOT flip the UI to
            // "checked in" — otherwise the receiver sees "you're all set"
            // for a check-in that was never recorded.
            errorMessage = error.localizedDescription
        }

        isCheckingIn = false
    }

    /// Open the post-check-in undo window and auto-close it when the grace
    /// period lapses so the button can't linger past the server-side limit.
    private func startUndoWindow() {
        let deadline = Date().addingTimeInterval(Self.undoGraceSeconds)
        undoableUntil = deadline
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoGraceSeconds))
            guard let self else { return }
            // Only clear if it's still the same window we opened (a later
            // check-in may have re-opened it).
            if self.undoableUntil == deadline { self.undoableUntil = nil }
        }
    }

    /// Undo the just-recorded check-in (US-IOS048). Reverses the server row,
    /// re-opens any requests it closed, and returns the UI to the pre-check-in
    /// state. No-op once the grace window has lapsed.
    func undoCheckIn() async {
        guard let familyId, let until = undoableUntil, until > Date(), !isUndoing else { return }
        isUndoing = true
        defer { isUndoing = false }
        do {
            try await CheckInService.shared.undoLastCheckIn(familyId: familyId)
            // Roll the UI back to "not yet checked in".
            hasCheckedInToday = false
            lastCheckIn = nil
            selectedMood = nil
            undoableUntil = nil
            SharedCheckInPublisher.clear()
            // Re-evaluate the pending request and fallback reminder, since the
            // server may have re-opened a request the undo restored.
            await loadStatus()
            DailyOKHaptics.warning()
            Task { await AnalyticsService.shared.track(.checkInUndone) }
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
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
