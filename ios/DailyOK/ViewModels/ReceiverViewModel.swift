import SwiftUI
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
    /// Mood the receiver picked after checking in (optional, post-check-in).
    @Published var selectedMood: Mood?

    private let offlineService = OfflineCheckInService.shared

    /// Whether to show the optional "how are you feeling?" picker after a
    /// check-in: enabled in settings, an online check-in row exists to attach to,
    /// and no mood has been recorded yet.
    var shouldPromptForMood: Bool {
        guard receiverSettings?.moodTrackingEnabled == true else { return false }
        guard let checkIn = lastCheckIn, checkIn.mood == nil else { return false }
        return selectedMood == nil
    }

    func loadStatus() async {
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
        #if DEBUG
        print("[ReceiverViewModel] loadStatus: tz=\(tzRow?.timezone ?? "nil") todayCheckIn=\(todayCheckIn?.checkedInAt.description ?? "nil")")
        #endif
        lastCheckIn = todayCheckIn
        hasCheckedInToday = (todayCheckIn != nil)
        // A fresh load reflects server truth — clear any locally-picked mood so
        // the prompt reappears only if today's row genuinely has no mood yet.
        selectedMood = todayCheckIn?.mood

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
            streakDays = Streaks.currentStreak(isoTimestamps: isoTimestamps, calendar: cal)
            consistencyPercent = Streaks.consistencyPercent(isoTimestamps: isoTimestamps, windowDays: 7, calendar: cal)
        }

        await loadReceiverSettings(userId: session.user.id, familyId: family.id)

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
        hasPendingRequest = !(requests?.isEmpty ?? true)
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
        guard let (hour, minute) = Self.parseCheckinTime(settings.checkinTime) else { return nil }

        let calendar = Calendar.current
        let now = Date()
        // Find the next occurrence of the check-in time at or after `now`. Using
        // `nextDate(after:matching:)` (rather than `bySettingHour` + add-a-day)
        // correctly skips a wall-clock time that doesn't exist on the DST
        // spring-forward day instead of producing an hour-off or invalid target.
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let target = calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime
        ) else { return nil }

        return calendar.date(byAdding: .minute, value: settings.gracePeriodMinutes, to: target)
    }

    /// Parse a stored "HH:mm[:ss]" check-in time into hour/minute components.
    nonisolated static func parseCheckinTime(_ raw: String) -> (hour: Int, minute: Int)? {
        let parts = raw.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
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

    private func computeNextCheckInTime(from settings: ReceiverSettings) {
        guard let (hour, minute) = Self.parseCheckinTime(settings.checkinTime) else { return }

        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        // Next occurrence of the check-in time strictly after now (DST-safe).
        nextCheckInTime = calendar.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        )
    }

    func performCheckIn() async {
        guard let familyId, !isCheckingIn else { return }

        isCheckingIn = true
        errorMessage = nil

        do {
            let checkIn = try await offlineService.performCheckIn(
                familyId: familyId,
                mood: nil,
                source: .app
            )

            if let checkIn {
                lastCheckIn = checkIn
            }
            hasCheckedInToday = true
            hasPendingRequest = false
            selectedMood = nil
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
