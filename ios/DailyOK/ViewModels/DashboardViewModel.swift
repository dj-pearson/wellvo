import SwiftUI
import Supabase

struct ReceiverStatusCard: Identifiable {
    let id: UUID
    let memberId: UUID
    let name: String
    let avatarUrl: String?
    /// Receiver's phone number (E.164/raw), if known — drives one-tap call /
    /// FaceTime / message quick actions. Nil hides those actions.
    var phone: String?
    var status: ReceiverCheckInStatus
    var lastCheckIn: Date?
    var streak: Int
    var consistencyPercent: Int = 0
    var mood: Mood?
    /// False only when the server positively reports no active push token for
    /// this receiver. Unknown (lookup failed / older backend) reads as true so
    /// the card never shows a false "hasn't enabled notifications" warning.
    var hasNotificationsEnabled: Bool
    var checkedInTime: Date? // Time component only, for timeline
    var locationLabel: String?
    var kidResponseType: String?
    /// Current escalation step of an active (pending) request: 0 = none yet,
    /// 1+ = reminders/alerts in progress. Drives the owner "escalating" banner.
    /// Always 0 once a caregiver has stood the request down.
    var escalationStep: Int = 0
    /// When the unanswered request was raised (its `created_at`) — i.e. when the
    /// check-in became due. Used as the Live Activity's "overdue since" anchor so
    /// it survives an app restart instead of resetting to now. Nil = not overdue.
    var escalationDueSince: Date? = nil
    /// US-IOS016: number of shared care notes on this receiver, for the card badge.
    var noteCount: Int = 0
    /// US-IOS017: optional passive "active today" signal (Apple Health, opt-in).
    /// Supplements — never replaces — an explicit check-in. Nil = not shared.
    var passiveActiveToday: Bool? = nil
    /// Receiver's IANA zone. Every receiver-side time on the card is shown in
    /// it (labelled when it differs from this device's zone).
    var timezone: String? = nil
    /// One plain-language line under the status: "Due at 10:00 AM", "Asked at
    /// 9:00 AM · no answer yet", "Snoozed until 9:45 AM", "Asked for help at …".
    var statusDetail: String? = nil
    /// Set when today's check-in asked for help (need help / call me / kid SOS).
    var helpKind: HelpKind? = nil
    /// A caregiver stood the unanswered request down ("I've reached them").
    var stoodDown: Bool = false
    var stoodDownAt: Date? = nil
    /// When the escalation's next step fires, for the plain-language banner.
    var nextEscalationAt: Date? = nil
    /// False when the owner turned escalation off for this receiver — no alert
    /// will come if they don't answer, so the card says so.
    var escalationEnabled: Bool = true
    /// Minutes between escalation steps (receiver_settings, 30 by default).
    /// A co-caregiver is alerted one step after the owner, so their card can
    /// say when. Nil = unknown.
    var reminderIntervalMinutes: Int? = nil
    /// The unanswered request behind a Pending / Missed card, and who said
    /// "I'm on it" for it (00062) — so the owner and co-caregivers don't all
    /// call at once.
    var requestId: UUID? = nil
    var claimedBy: UUID? = nil
    var claimedByName: String? = nil
    var claimedAt: Date? = nil
    /// Phone health from the receiver's heartbeat (users.last_seen_at /
    /// last_battery_level, 0…1) — tells "phone is dead" from "not answering".
    var lastSeenAt: Date? = nil
    var batteryLevel: Double? = nil

    /// Sort key: the receiver who needs attention first. Ties break on name so
    /// the order is stable across refreshes.
    var urgencyRank: Int {
        switch status {
        case .needsHelp: return 0
        case .missed: return stoodDown ? 5 : 1
        case .pending:
            if stoodDown { return 5 }
            return escalationStep >= 1 ? 2 : 3
        case .noData: return 4
        case .upcoming: return 6
        case .checkedIn: return 7
        }
    }

    /// Needs the owner's attention right now (drives the alert background tone
    /// and the headline).
    var needsAttention: Bool {
        switch status {
        case .needsHelp: return true
        case .missed: return !stoodDown
        case .pending: return !stoodDown && escalationStep >= 1
        default: return false
        }
    }
}

/// What an urgent check-in asked for. Kid SOS is its own kind so the card can
/// say "SOS" rather than a generic "needs help".
enum HelpKind: Equatable {
    case needHelp
    case callMe
    case sos

    var label: String {
        switch self {
        case .needHelp: return "Asked for help"
        case .callMe: return "Wants a call"
        case .sos: return "Sent SOS"
        }
    }
}

enum ReceiverCheckInStatus {
    case checkedIn
    case pending
    case missed
    case noData
    /// Today's check-in asked for help (need help / call me / kid SOS). Outranks
    /// "checked in": a help request is not reassurance.
    case needsHelp
    /// Nothing is due yet — before today's first scheduled time, a day with no
    /// check-in scheduled, or a paused schedule. Neutral, not "pending".
    case upcoming

    var label: String {
        switch self {
        case .checkedIn: return "Checked In"
        case .pending: return "Pending"
        case .missed: return "Missed"
        case .noData: return "No Data"
        case .needsHelp: return "Needs Help"
        case .upcoming: return "Not Due Yet"
        }
    }

    /// Default status colors. Pending uses a deep amber in light mode — plain
    /// `.yellow` text is close to unreadable on the light glass surface, and
    /// "Pending" is the most important word on the card.
    var color: Color {
        switch self {
        case .checkedIn: return .green
        case .pending: return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .systemYellow
                : UIColor(red: 0.66, green: 0.46, blue: 0.03, alpha: 1)
        })
        case .missed, .needsHelp: return .red
        case .noData, .upcoming: return .gray
        }
    }

    /// Stronger, deeper shades for Increase Contrast — the default `.yellow`
    /// (pending) in particular is low-contrast on light surfaces (US-IOS106).
    func color(increasedContrast: Bool) -> Color {
        guard increasedContrast else { return color }
        switch self {
        case .checkedIn: return Color(red: 0.11, green: 0.47, blue: 0.15)
        case .pending: return Color(red: 0.66, green: 0.46, blue: 0.03)
        case .missed, .needsHelp: return Color(red: 0.78, green: 0.0, blue: 0.0)
        case .noData, .upcoming: return Color(.darkGray)
        }
    }

    var icon: String {
        switch self {
        case .checkedIn: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .missed: return "exclamationmark.circle.fill"
        case .noData: return "minus.circle.fill"
        case .needsHelp: return "exclamationmark.bubble.fill"
        case .upcoming: return "calendar.badge.clock"
        }
    }
}

/// Where today's schedule stands for a receiver, in their own time zone.
enum ReceiverScheduleState: Equatable {
    /// No settings loaded (older backend / read failed): legacy "Pending".
    case unknown
    case paused
    case offToday
    /// Today's first check-in is still ahead.
    case notYetDue(Date)
    /// Today's (latest passed) check-in time has gone by.
    case due(Date)
}

/// Receiver-side times ("checked in 8:05 AM") shown in the receiver's zone,
/// with the zone abbreviation when it differs from this device's — an owner in
/// New York otherwise reads a Los Angeles parent's 8:05 as 11:05.
enum ReceiverTime {
    static func format(_ date: Date, timezone: String?, device: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        guard let id = timezone, let tz = TimeZone(identifier: id),
              tz.secondsFromGMT(for: date) != device.secondsFromGMT(for: date) else {
            formatter.timeZone = device
            return formatter.string(from: date)
        }
        formatter.timeZone = tz
        let abbreviation = tz.abbreviation(for: date) ?? id
        return "\(formatter.string(from: date)) \(abbreviation)"
    }

    /// Date + time, for check-ins that aren't today's.
    static func formatDateTime(_ date: Date, timezone: String?, device: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        guard let id = timezone, let tz = TimeZone(identifier: id),
              tz.secondsFromGMT(for: date) != device.secondsFromGMT(for: date) else {
            formatter.timeZone = device
            return formatter.string(from: date)
        }
        formatter.timeZone = tz
        return "\(formatter.string(from: date)) \(tz.abbreviation(for: date) ?? id)"
    }
}

/// Result of a "Check on" tap, so the card can be honest about delivery.
enum CheckOnOutcome: Equatable {
    /// Sent. `deliveredDevices` is nil on older servers that don't report it.
    case sent(deliveredDevices: Int?)
    case failed
}

/// Everything status resolution decides for one receiver.
struct ResolvedReceiverStatus {
    var status: ReceiverCheckInStatus
    var escalationStep: Int
    var dueSince: Date?
    /// The request still waiting on the receiver, if any.
    var request: CheckInRequest?
    var stoodDown: Bool
    var stoodDownAt: Date?
    var helpKind: HelpKind?
}

struct WeeklySummary {
    var consistencyPercentage: Double
    var averageCheckInTime: String
    var totalCheckIns: Int
    var totalExpected: Int
    var moodBreakdown: [Mood: Int]
    /// Receivers below 80% of their scheduled days this week, worst first
    /// (e.g. "Dad: 3 of 7 days"), so a family average can't hide one person
    /// slipping.
    var lagging: [String] = []

    /// Nothing was scheduled this week (new receiver, all paused): show "—",
    /// never a reassuring "100% Good".
    var hasData: Bool { totalExpected > 0 }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var family: Family?
    @Published var receiverCards: [ReceiverStatusCard] = []
    @Published var weeklySummary: WeeklySummary?
    @Published var alerts: [DailyOKAlert] = []
    @Published var isLoading = false
    /// Load failure with nothing to show (empty state), or a failed owner
    /// ACTION (check-on, stand down, dismiss/acknowledge) — shown as an alert.
    @Published var errorMessage: String?
    /// A background refresh failed while cards are on screen. Shown as a quiet
    /// inline strip ("showing status from 9:14"), never as a modal: reloads run
    /// on every foreground / tab switch / realtime event, and a modal on each
    /// one while offline is nagging, not information.
    @Published var refreshError: String?
    /// When the cards on screen were last loaded successfully.
    @Published var lastUpdatedAt: Date?
    /// Signed-in user, for "Release" on the caller's own claim and the
    /// per-user walkthrough flag.
    @Published var currentUserId: UUID?
    /// Active receivers' membership rows keyed by receiver user id, so an
    /// owner's card can open that receiver's schedule & alerts.
    @Published var receiverMembers: [UUID: FamilyMember] = [:]
    /// The family owner's name, so a co-caregiver's screens can say who was
    /// alerted before them, who hears when they stop the alerts, and who to
    /// ask about alert settings ("Ask Sarah"). Nil until loaded or when the
    /// owner has no membership row.
    @Published var ownerName: String?
    /// The signed-in user may stop alerts and send "Check on now" for this
    /// family's receivers: its owner or an active co-caregiver (the server
    /// checks the same, cancel-escalation / on-demand-checkin). Everything
    /// else on the dashboard that changes the family stays owner-only.
    @Published private(set) var canActOnEscalations = false
    /// Signed in, but the server says this user is in no family any more
    /// (removed, family deleted). Distinct from "family has nobody to check on
    /// yet": the view says so and re-resolves the role instead of promising
    /// people will appear.
    @Published var familyMissing = false
    /// Alerts with a claim / release in flight, so "I've got this" can't be
    /// sent twice and shows progress on a slow network.
    @Published var acknowledgingAlertIds: Set<UUID> = []
    /// Cards with an "I'm on it" / release in flight.
    @Published var claimingCardIds: Set<UUID> = []
    /// Set true when a milestone (a receiver reaching a multi-day streak) makes
    /// this a good moment to ask for an App Store rating. The view observes this
    /// and presents the system prompt, then resets it.
    @Published var shouldRequestReview = false

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeFamilyId: UUID?
    private var realtimeListenerTask: Task<Void, Never>?
    private var pendingRefreshTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    /// A reload was asked for while one was in flight. The in-flight load may
    /// already have read the rows the new event changed (e.g. the receiver
    /// tapped I'm OK mid-load), so one more pass runs when it finishes.
    private var reloadRequested = false

    /// Coalesce the many reload triggers (`.task`, `scenePhase == .active`, tab
    /// switch, realtime, offline-sync, pull-to-refresh). Without this, `.task`
    /// and `scenePhase == .active` both fire on launch and kick off two
    /// concurrent full loads that race on the `@Published` arrays. Re-entrant
    /// callers await the in-flight load instead of starting a new one — and
    /// flag that one more pass is needed, so an event that arrives mid-load is
    /// never dropped (the dashboard used to stay on "Pending" after the
    /// receiver checked in).
    func loadDashboard() async {
        if let loadTask {
            reloadRequested = true
            return await loadTask.value
        }
        // Clear the handle from INSIDE the task rather than after
        // `await task.value` in the caller. The caller is usually a view's
        // `.task`, which is cancelled on disappear; if it's torn down at the
        // suspension below, a caller-side `loadTask = nil` would never run,
        // leaving a completed task cached forever — every later loadDashboard()
        // would return its stale value instantly and the dashboard would stop
        // refreshing. The unstructured task finishes regardless and clears itself.
        let task = Task { [weak self] in
            var passes = 0
            repeat {
                self?.reloadRequested = false
                await self?.performLoad()
                passes += 1
            } while (self?.reloadRequested ?? false) && passes < 3
            self?.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        // Only clear a message that belongs to the empty state; an action
        // error the owner hasn't read yet must survive a realtime reload.
        if receiverCards.isEmpty { errorMessage = nil }

        do {
            // Without a session (e.g. offline with an expired token) getFamily
            // returns nil — that is a failed refresh, not "no family".
            guard let session = try? await SupabaseService.shared.client.auth.session else {
                throw DailyOKError.auth(String(localized: "Couldn't confirm you're signed in. Check your connection and try again."))
            }
            currentUserId = session.user.id

            family = try await FamilyService.shared.getFamily()
            guard let family else {
                // Signed in, but no longer in a family (removed as a viewer,
                // family deleted): don't keep showing — or publishing to the
                // Lock Screen widget — the last family's status.
                await clearFamilyState()
                familyMissing = true
                isLoading = false
                return
            }
            familyMissing = false
            // Mirror the grandfather deadline so subscription gating can honor it
            // (US-IOS097).
            SubscriptionService.shared.freeTierExpiresAt = family.freeTierExpiresAt

            let members = try await FamilyService.shared.getFamilyMembers(familyId: family.id)
            let receivers = members.filter { $0.role == .receiver && $0.status == .active }
            let owner = members.first { $0.userId == family.ownerId }?.user
            ownerName = owner.map(\.displayName).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            canActOnEscalations = Self.mayActOnEscalations(
                ownerId: family.ownerId,
                currentUserId: currentUserId,
                members: members
            )
            receiverMembers = Dictionary(receivers.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })

            // Which receivers have notifications on — one RPC for all of them.
            // nil = unknown, which never shows the warning.
            let notifiedUserIds = await activeNotificationUserIds(familyId: family.id)

            // Batch each receiver's schedule (one query) so consistency can be
            // judged against the days they were actually scheduled to check in
            // (US-IOS075) and the card can say "Due at 10:00 AM". Co-caregivers
            // can't read receiver_settings (RLS), so theirs come from the
            // family_receiver_schedules RPC (00057).
            let settingsByMember = await receiverSettingsByMember(memberIds: receivers.map(\.id), familyId: family.id)

            var cards: [ReceiverStatusCard] = []
            var weeklyCheckIns: [CheckIn] = []
            // Aggregate a fair, schedule-aware family consistency for the weekly
            // summary instead of assuming 7 expected days per receiver.
            var totalScheduledDays = 0
            var totalCheckedInDays = 0
            var perReceiverWeek: [(name: String, checkedIn: Int, scheduled: Int)] = []
            // Average check-in time accumulated in each receiver's own timezone.
            var weekMinutesTotal = 0
            var weekMinutesCount = 0
            let now = Date()

            for receiver in receivers {
                let receiverTz = receiver.user?.timezone
                let receiverCal = Calendar.forTimezone(receiverTz)
                let settings = settingsByMember[receiver.id]

                // Overlap the three independent reads for this receiver.
                async let todayCheckInResult = CheckInService.shared.todayCheckInStatus(
                    receiverId: receiver.userId,
                    familyId: family.id,
                    timezone: receiverTz
                )
                async let historyResult = CheckInService.shared.checkInHistory(
                    receiverId: receiver.userId,
                    familyId: family.id,
                    days: 30
                )
                async let activeRequestResult = latestActiveRequest(
                    receiverId: receiver.userId,
                    familyId: family.id
                )

                let todayCheckIn = try await todayCheckInResult
                let history = try await historyResult
                // We must ALWAYS resolve against the latest active (pending/missed)
                // request — not only when there's no check-in today — otherwise an
                // on-demand request sent after a routine morning check-in would be
                // masked by "checked in today" and falsely reassure the owner.
                // It throws like the other two: resolving WITHOUT it (it used to
                // be `try?`) showed a green "Checked In" over a running escalation
                // whenever this one query failed.
                let activeRequest = try await activeRequestResult

                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let isoTimestamps = history.map { isoFormatter.string(from: $0.checkedInAt) }

                // Same streak rule as the receiver's home screen: today counts
                // once it's done, but a not-yet-done today doesn't zero the
                // streak every morning.
                let streak = Streaks.currentStreak(isoTimestamps: isoTimestamps, calendar: receiverCal, today: now)

                // Bucket consistency days in the receiver's timezone so the
                // dashboard chip agrees with their "checked in today" status, and
                // only count days they were scheduled to check in (US-IOS075).
                let consistencyResult = Streaks.scheduleConsistency(
                    isoTimestamps: isoTimestamps,
                    scheduledWeekdays: settings?.scheduledWeekdays,
                    windowDays: 7,
                    calendar: receiverCal
                )
                let consistency = consistencyResult.percent
                totalScheduledDays += consistencyResult.scheduledDays
                totalCheckedInDays += consistencyResult.checkedInDays
                perReceiverWeek.append((
                    name: receiver.user?.displayName ?? "Unknown",
                    checkedIn: consistencyResult.checkedInDays,
                    scheduled: consistencyResult.scheduledDays
                ))

                // Collect last 7 days for weekly summary, bucketed in the
                // receiver's timezone (US-IOS100).
                let sevenDaysAgo = receiverCal.date(byAdding: .day, value: -7, to: now)
                    ?? now.addingTimeInterval(-7 * 86_400)
                let recentCheckIns = history.filter { $0.checkedInAt >= sevenDaysAgo }
                weeklyCheckIns.append(contentsOf: recentCheckIns)
                for ci in recentCheckIns {
                    let comps = receiverCal.dateComponents([.hour, .minute], from: ci.checkedInAt)
                    weekMinutesTotal += (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                    weekMinutesCount += 1
                }

                let schedule = Self.scheduleState(settings: settings, now: now, calendar: receiverCal)
                let resolved = Self.resolveStatus(
                    todayCheckIn: todayCheckIn,
                    activeRequest: activeRequest,
                    latestCheckInAt: history.first?.checkedInAt,
                    schedule: schedule
                )

                cards.append(ReceiverStatusCard(
                    id: receiver.userId,
                    memberId: receiver.id,
                    name: receiver.user?.displayName ?? "Unknown",
                    avatarUrl: receiver.user?.avatarUrl,
                    phone: receiver.user?.phone,
                    status: resolved.status,
                    lastCheckIn: todayCheckIn?.checkedInAt ?? history.first?.checkedInAt,
                    streak: streak,
                    consistencyPercent: consistency,
                    mood: todayCheckIn?.mood,
                    hasNotificationsEnabled: notifiedUserIds.map { $0.contains(receiver.userId) } ?? true,
                    checkedInTime: todayCheckIn?.checkedInAt,
                    locationLabel: todayCheckIn?.locationLabel,
                    kidResponseType: todayCheckIn?.kidResponseType,
                    escalationStep: resolved.escalationStep,
                    escalationDueSince: resolved.dueSince,
                    timezone: receiverTz,
                    statusDetail: Self.statusDetail(
                        resolved: resolved,
                        todayCheckIn: todayCheckIn,
                        schedule: schedule,
                        timezone: receiverTz,
                        now: now
                    ),
                    helpKind: resolved.helpKind,
                    stoodDown: resolved.stoodDown,
                    stoodDownAt: resolved.stoodDownAt,
                    nextEscalationAt: resolved.stoodDown ? nil : resolved.request?.nextEscalationAt,
                    escalationEnabled: settings?.escalationEnabled ?? true,
                    reminderIntervalMinutes: settings?.reminderIntervalMinutes,
                    requestId: resolved.stoodDown ? nil : resolved.request?.id,
                    claimedBy: resolved.stoodDown ? nil : resolved.request?.claimedBy,
                    claimedByName: resolved.stoodDown ? nil : resolved.request?.claimedByName,
                    claimedAt: resolved.stoodDown ? nil : resolved.request?.claimedAt,
                    lastSeenAt: receiver.user?.lastSeenAt,
                    batteryLevel: receiver.user?.lastBatteryLevel
                ))
            }

            // Most urgent first; name breaks ties so the order is stable (the
            // member query has no ORDER BY, so cards used to shuffle).
            cards.sort { lhs, rhs in
                lhs.urgencyRank != rhs.urgencyRank
                    ? lhs.urgencyRank < rhs.urgencyRank
                    : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            receiverCards = cards
            // US-IOS016: tally shared care notes per receiver for the card badge.
            await applyNoteCounts(familyId: family.id)
            // US-IOS017: apply any opt-in passive "active today" signals.
            await applyWellnessSignals(familyId: family.id)
            // Mirror status to the App Group so the owner status widget can show
            // an at-a-glance summary without opening the app.
            SharedOwnerPublisher.publish(receiverCards)
            // Start/refresh/end Live Activities for any receiver in escalation.
            // The owner and active co-caregivers both get "Stand down" (it
            // still asks for confirmation in the app).
            EscalationActivityManager.sync(
                cards: receiverCards,
                familyId: family.id,
                canStandDown: canActOnEscalations
            )
            weeklySummary = computeWeeklySummary(
                checkIns: weeklyCheckIns,
                totalScheduledDays: totalScheduledDays,
                totalCheckedInDays: totalCheckedInDays,
                avgCheckInMinutes: weekMinutesCount > 0 ? weekMinutesTotal / weekMinutesCount : nil,
                lagging: Self.laggingReceivers(perReceiverWeek)
            )
            // A receiver hitting a strong streak is a high-satisfaction moment —
            // flag it so the view can ask for a rating (gated + throttled in the
            // service, so this only fires occasionally and never offline).
            if ReviewPromptService.shared.shouldPromptForOwnerStreak(maxStreak: cards.map(\.streak).max() ?? 0) {
                shouldRequestReview = true
            }
            await loadAlerts(familyId: family.id)
            await subscribeToRealtime(familyId: family.id)
            lastUpdatedAt = Date()
            refreshError = nil
        } catch {
            let message = error.localizedDescription
            if receiverCards.isEmpty {
                errorMessage = message
            } else {
                refreshError = message
            }
        }

        isLoading = false
    }

    /// The family is gone for this user: drop everything derived from it,
    /// including the Lock Screen widget and any running Live Activity.
    private func clearFamilyState() async {
        receiverCards = []
        receiverMembers = [:]
        ownerName = nil
        canActOnEscalations = false
        alerts = []
        weeklySummary = nil
        refreshError = nil
        lastUpdatedAt = nil
        SharedOwnerPublisher.clear()
        EscalationActivityManager.endAll()
        await teardownRealtime()
    }

    /// Sends an on-demand check-in. `.sent(deliveredDevices: 0)` means the
    /// request was saved but no phone could be notified — the card says so and
    /// offers a call instead of a green "Request sent".
    func sendOnDemandCheckIn(to receiverId: UUID) async -> CheckOnOutcome {
        guard let family else { return .failed }
        do {
            let result = try await CheckInService.shared.requestOnDemandCheckIn(
                receiverId: receiverId,
                familyId: family.id
            )
            return .sent(deliveredDevices: result.deliveredDevices)
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
            return .failed
        }
    }

    /// Caregiver "stand down" (owner or active co-caregiver) — stop the
    /// escalation chain for a receiver after reaching them another way. Returns true on success. The server records
    /// the stand-down on the request (00055), so the reload that follows keeps
    /// the banner and Live Activity gone instead of bringing them back; the
    /// card is updated immediately for feedback.
    @discardableResult
    func standDownEscalation(for receiverId: UUID) async -> Bool {
        guard let family else { return false }
        do {
            let result = try await CheckInService.shared.cancelEscalation(receiverId: receiverId, familyId: family.id)
            if let idx = receiverCards.firstIndex(where: { $0.id == receiverId }) {
                receiverCards[idx].escalationStep = 0
                receiverCards[idx].escalationDueSince = nil
                receiverCards[idx].nextEscalationAt = nil
                receiverCards[idx].stoodDown = true
                receiverCards[idx].stoodDownAt = result.stoodDownAt ?? Date()
                receiverCards[idx].statusDetail = Self.stoodDownDetail(
                    at: receiverCards[idx].stoodDownAt,
                    timezone: nil
                )
            }
            // End the Live Activity right away — only after the cancel succeeded,
            // so a failed stand-down does NOT visually clear an active escalation
            // (US-IOS081/US-IOS083).
            EscalationActivityManager.end(receiverId: receiverId.uuidString)
            SharedOwnerPublisher.publish(receiverCards)
            return true
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
            return false
        }
    }

    /// "I'm on it" (or release) for the unanswered request behind a card. The
    /// row change reaches the other caregivers through the realtime
    /// subscription on checkin_requests.
    func claimRequest(for cardId: UUID, release: Bool) async {
        guard let idx = receiverCards.firstIndex(where: { $0.id == cardId }),
              let requestId = receiverCards[idx].requestId,
              !claimingCardIds.contains(cardId) else { return }
        claimingCardIds.insert(cardId)
        defer { claimingCardIds.remove(cardId) }
        let name = receiverCards[idx].name
        do {
            let row = try await CheckInService.shared.claimCheckInRequest(requestId: requestId, release: release)
            if let i = receiverCards.firstIndex(where: { $0.id == cardId }) {
                receiverCards[i].claimedBy = row.claimedBy
                receiverCards[i].claimedByName = row.claimedByName
                receiverCards[i].claimedAt = row.claimedAt
            }
            if !release, let currentUserId, let holder = row.claimedBy, holder != currentUserId {
                errorMessage = String(localized: "\(row.claimedByName ?? String(localized: "Another caregiver")) is already on it.")
            } else if !release, row.claimedBy == nil {
                // Answered or stood down in the meantime: nothing to claim.
                await loadDashboard()
            } else {
                DailyOKHaptics.success()
                UIAccessibility.post(
                    notification: .announcement,
                    argument: release
                        ? String(localized: "Released. Other caregivers can take this on.")
                        : String(localized: "You're on it for \(name). Other caregivers can see that.")
                )
            }
        } catch where Self.isMissingRPC(error, named: "claim_checkin_request") {
            errorMessage = String(localized: "Saying \"I'm on it\" isn't available yet. Call or text the other caregivers instead.")
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    /// Owner, or an active co-caregiver of this family: may stop alerts and
    /// send "Check on now". Receivers and removed or invited members may not.
    nonisolated static func mayActOnEscalations(
        ownerId: UUID,
        currentUserId: UUID?,
        members: [FamilyMember]
    ) -> Bool {
        guard let currentUserId else { return false }
        if ownerId == currentUserId { return true }
        return members.contains {
            $0.userId == currentUserId && $0.role == .viewer && $0.status == .active
        }
    }

    /// "Tom is on it (10:42 AM)" / "You're on it (10:42 AM)".
    nonisolated static func claimLine(name: String?, at: Date?, isMine: Bool) -> String {
        let when = at.map { " (\($0.formatted(date: .omitted, time: .shortened)))" } ?? ""
        return isMine ? "You're on it\(when)" : "\(name ?? "A caregiver") is on it\(when)"
    }

    // MARK: - Pure status resolution (unit-tested)

    /// Responding to a check-in request marks it `checked_in` server-side, so an
    /// active (pending/missed) request that was created AFTER the most recent
    /// check-in means the receiver has NOT yet responded to *that* request — even
    /// if they did a routine check-in earlier in the day. In that case we surface
    /// the request (and its escalation step) instead of a stale "checked in".
    ///
    /// `latestCheckInAt` is the newest check-in on ANY day. A missed row is
    /// never closed server-side (only pending rows are), so without it a single
    /// miss last Tuesday resurfaced as "Missed — alerts were sent" every
    /// morning before the day's first check-in.
    nonisolated static func resolveStatus(
        todayCheckIn: CheckIn?,
        activeRequest: CheckInRequest?,
        latestCheckInAt: Date? = nil,
        schedule: ReceiverScheduleState = .unknown
    ) -> ResolvedReceiverStatus {
        let answeredAt = [todayCheckIn?.checkedInAt, latestCheckInAt].compactMap { $0 }.max()

        let unanswered: CheckInRequest?
        if let req = activeRequest, !(answeredAt.map { $0 >= req.createdAt } ?? false) {
            unanswered = req
        } else {
            unanswered = nil
        }

        // Stood down: recorded by the server (00055), or — on a backend
        // without the column — inferred from a cleared escalation clock on a
        // request that had already started escalating. escalation_tick always
        // sets next_escalation_at when it steps, so only cancel-escalation
        // leaves a stepped, pending request with no next step.
        // A PENDING request with a stand-down record but a live escalation
        // clock has been re-armed since (the receiver snoozed it, or undid a
        // check-in — both reschedule next_escalation_at without clearing
        // stood_down_at): escalation is running again, so it is not stood down.
        let stoodDown: Bool
        if let req = unanswered {
            let recorded = req.stoodDownAt != nil
                && (req.status == .missed || req.nextEscalationAt == nil)
            stoodDown = recorded
                || (req.status == .pending && req.escalationStep >= 1 && req.nextEscalationAt == nil)
        } else {
            stoodDown = false
        }

        let help = Self.helpKind(for: todayCheckIn)

        let status: ReceiverCheckInStatus
        if help != nil {
            status = .needsHelp
        } else if let req = unanswered {
            status = req.status == .missed ? .missed : .pending
        } else if todayCheckIn != nil {
            status = .checkedIn
        } else {
            switch schedule {
            case .paused, .offToday, .notYetDue: status = .upcoming
            case .due, .unknown: status = .pending
            }
        }

        // `createdAt` is when the request was raised — i.e. when the check-in
        // became due. The Live Activity uses it as the real "overdue since" time.
        return ResolvedReceiverStatus(
            status: status,
            escalationStep: stoodDown ? 0 : (unanswered?.escalationStep ?? 0),
            dueSince: stoodDown ? nil : unanswered?.createdAt,
            request: unanswered,
            stoodDown: stoodDown,
            stoodDownAt: stoodDown ? unanswered?.stoodDownAt : nil,
            helpKind: help
        )
    }

    /// Today's check-in asked for help. Kid SOS is recorded server-side as a
    /// need_help alert, but the check-in row keeps kid_response_type = "sos".
    nonisolated static func helpKind(for checkIn: CheckIn?) -> HelpKind? {
        guard let checkIn else { return nil }
        if checkIn.kidResponseType == KidResponseType.sos.rawValue { return .sos }
        switch checkIn.responseType ?? .ok {
        case .needHelp: return .needHelp
        case .callMe: return .callMe
        case .ok: return nil
        }
    }

    /// Where today's schedule stands, evaluated in the receiver's calendar.
    nonisolated static func scheduleState(
        settings: ReceiverSettings?,
        now: Date,
        calendar: Calendar
    ) -> ReceiverScheduleState {
        guard let settings else { return .unknown }
        if settings.schedulePaused { return .paused }

        let times = ReceiverViewModel.scheduledTimes(for: settings, on: now, calendar: calendar)
        let slots: [Date] = times.compactMap { (raw: String) -> Date? in
            guard let (hour, minute) = ReceiverViewModel.parseCheckinTime(raw) else { return nil }
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            return calendar.date(from: comps)
        }.sorted()

        guard let first = slots.first else { return .offToday }
        if first > now { return .notYetDue(first) }
        return .due(slots.last(where: { $0 <= now }) ?? first)
    }

    /// The one-line explanation under the status.
    nonisolated static func statusDetail(
        resolved: ResolvedReceiverStatus,
        todayCheckIn: CheckIn?,
        schedule: ReceiverScheduleState,
        timezone: String?,
        now: Date = Date()
    ) -> String? {
        if let kind = resolved.helpKind, let at = todayCheckIn?.checkedInAt {
            return "\(kind.label) at \(ReceiverTime.format(at, timezone: timezone))"
        }
        if resolved.stoodDown {
            return stoodDownDetail(at: resolved.stoodDownAt, timezone: nil)
        }
        if let req = resolved.request {
            let asked = Calendar.forTimezone(timezone).isDate(req.createdAt, inSameDayAs: now)
                ? ReceiverTime.format(req.createdAt, timezone: timezone)
                : ReceiverTime.formatDateTime(req.createdAt, timezone: timezone)
            if req.status == .missed {
                return "No answer since \(asked)"
            }
            if let until = req.snoozedUntil, until > now {
                return "Snoozed until \(ReceiverTime.format(until, timezone: timezone))"
            }
            return "Asked at \(asked) · no answer yet"
        }
        if let at = todayCheckIn?.checkedInAt {
            return "Checked in at \(ReceiverTime.format(at, timezone: timezone))"
        }
        switch schedule {
        case .paused: return "Check-ins are paused"
        case .offToday: return "No check-in scheduled today"
        case .notYetDue(let at): return "Due at \(ReceiverTime.format(at, timezone: timezone))"
        case .due(let at): return "Was due at \(ReceiverTime.format(at, timezone: timezone))"
        case .unknown: return nil
        }
    }

    /// What the escalation has done and what happens next, for the person
    /// reading it. escalation-tick alerts the owner at step 2 and co-caregivers
    /// at step 3 (one reminder interval later), so the owner's wording ("You've
    /// been alerted. Other caregivers will be alerted at …") was false on a
    /// co-caregiver's card: they hadn't been, and "other caregivers" was them.
    nonisolated static func escalationText(
        name: String,
        status: ReceiverCheckInStatus,
        step: Int,
        nextEscalationAt: Date?,
        reminderIntervalMinutes: Int?,
        isViewer: Bool,
        ownerName: String?,
        formatTime: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
    ) -> String {
        let next = nextEscalationAt.map { " at \(formatTime($0))" } ?? ""
        guard isViewer else {
            if status == .missed {
                return "\(name) didn't answer — all caregivers were alerted."
            }
            switch step {
            case 1:
                return "Reminder re-sent to \(name). You'll be alerted\(next) if there's still no answer."
            case 2:
                return "You've been alerted. Other caregivers will be alerted\(next) if there's still no answer."
            default:
                return "All caregivers have been alerted. \(name) still hasn't answered."
            }
        }

        let owner = ownerName ?? "The family owner"
        let ownerMid = ownerName ?? "the family owner"
        if status == .missed {
            return "\(name) didn't answer — \(ownerMid) and every co-caregiver, including you, were alerted."
        }
        switch step {
        case 1:
            // You're alerted one interval after the owner.
            if let at = nextEscalationAt {
                let yours = reminderIntervalMinutes.map { " and you at \(formatTime(at.addingTimeInterval(TimeInterval($0 * 60))))" }
                    ?? ", then you,"
                return "Reminder re-sent to \(name). \(owner) will be alerted\(next)\(yours) if there's still no answer."
            }
            return "Reminder re-sent to \(name). \(owner) will be alerted, then you, if there's still no answer."
        case 2:
            return "\(owner) has been alerted. You'll be alerted\(next) if there's still no answer."
        default:
            return "You and \(ownerMid) have been alerted. \(name) still hasn't answered."
        }
    }

    /// The card's "Escalation is off" line: an owner can fix it; a co-caregiver
    /// needs to know nobody (including them) will be alerted, and who to ask.
    nonisolated static func escalationOffText(name: String, isViewer: Bool, ownerName: String?) -> String {
        guard isViewer else {
            return "Escalation is off — you won't be alerted if \(name) doesn't answer."
        }
        let ask = ownerName.map { " Ask \($0) to turn them on." } ?? " The family owner can turn them on."
        return "Missed-check-in alerts are off for \(name) — nobody, including you, is alerted if they don't answer.\(ask)"
    }

    /// The "Stop alerts for Mom?" confirmation. A co-caregiver's stand-down
    /// is announced to the owner and the other co-caregivers, so they're told.
    nonisolated static func standDownConfirmMessage(name: String, isViewer: Bool, ownerName: String?) -> String {
        let base = "Only do this if you've confirmed \(name) is OK. It stops the reminders and caregiver alerts."
        guard isViewer else { return base }
        let who = ownerName.map { "\($0) and the other caregivers" } ?? "The family owner and the other caregivers"
        return "\(base) \(who) will be told you stopped them."
    }

    /// "Tom is handling this" — or "You're handling this" to Tom.
    nonisolated static func handlingLine(name: String?, isMine: Bool) -> String {
        isMine ? "You're handling this" : "\(name ?? "A caregiver") is handling this"
    }

    /// Stand-down times are the caregiver's own action — shown in this
    /// device's zone.
    nonisolated static func stoodDownDetail(at: Date?, timezone: String?) -> String {
        guard let at else { return "Alerts stopped — reached another way" }
        return "Alerts stopped at \(ReceiverTime.format(at, timezone: timezone))"
    }

    /// "Dad: 3 of 7 days" for anyone under 80% of their scheduled days, worst
    /// first.
    nonisolated static func laggingReceivers(_ rows: [(name: String, checkedIn: Int, scheduled: Int)]) -> [String] {
        rows
            .filter { $0.scheduled > 0 && Double($0.checkedIn) / Double($0.scheduled) < 0.8 }
            .sorted { Double($0.checkedIn) / Double($0.scheduled) < Double($1.checkedIn) / Double($1.scheduled) }
            .map { "\($0.name): \($0.checkedIn) of \($0.scheduled) days" }
    }

    /// Phone health line: "Phone active 12 min ago · 64%". `isWarning` when the
    /// phone may be off — not seen for 3h+ while an answer is outstanding, not
    /// seen for a day at all, or the battery is nearly flat.
    nonisolated static func deviceHealth(
        lastSeenAt: Date?,
        batteryLevel: Double?,
        answerOutstanding: Bool,
        now: Date = Date()
    ) -> (text: String, isWarning: Bool)? {
        guard let lastSeenAt else { return nil }
        let age = now.timeIntervalSince(lastSeenAt)
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        let seen = age < 60 ? "just now" : relative.localizedString(for: lastSeenAt, relativeTo: now)
        var text = "Phone active \(seen)"
        let battery = batteryLevel.flatMap { (0...1).contains($0) ? Int(($0 * 100).rounded()) : nil }
        if let battery { text += " · \(battery)% battery" }

        let lowBattery = (battery ?? 100) <= 10
        let warning = age >= 24 * 3600 || lowBattery || (answerOutstanding && age >= 3 * 3600)
        if warning { text += " — their phone may be off" }
        return (text, warning)
    }

    private func latestActiveRequest(receiverId: UUID, familyId: UUID) async throws -> CheckInRequest? {
        let requests: [CheckInRequest] = try await SupabaseService.shared.client
            .from("checkin_requests")
            .select()
            .eq("receiver_id", value: receiverId.uuidString)
            .eq("family_id", value: familyId.uuidString)
            .in("status", values: ["pending", "missed"])
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return requests.first
    }

    /// Alert types that mean someone may need help now. These sort first, are
    /// styled as urgent, and can't be dismissed until a caregiver has
    /// acknowledged them.
    nonisolated static let urgentAlertTypes: Set<String> = ["need_help", "call_me", "sos", "geofence_breach"]

    nonisolated static func isUrgent(_ alert: DailyOKAlert) -> Bool {
        urgentAlertTypes.contains(alert.type)
    }

    /// Alerts that are news, not something to act on: nobody needs to say
    /// "I've got this" about someone leaving the family, and offering it
    /// there makes a real claim mean less.
    nonisolated static let informationalAlertTypes: Set<String> = ["member_left"]

    nonisolated static func isClaimable(_ alert: DailyOKAlert) -> Bool {
        !informationalAlertTypes.contains(alert.type)
    }

    /// Urgent and unacknowledged first, then newest first.
    nonisolated static func sortAlerts(_ alerts: [DailyOKAlert]) -> [DailyOKAlert] {
        func rank(_ a: DailyOKAlert) -> Int {
            if isUrgent(a) { return a.isAcknowledged ? 1 : 0 }
            return 2
        }
        return alerts.sorted { lhs, rhs in
            rank(lhs) != rank(rhs) ? rank(lhs) < rank(rhs) : lhs.createdAt > rhs.createdAt
        }
    }

    func dismissAlert(_ alert: DailyOKAlert) async {
        do {
            // Ask for the updated rows back: an UPDATE that RLS filters out
            // (e.g. a viewer) "succeeds" with zero rows, and removing the alert
            // locally then made it reappear on the next reload.
            let updated: [DailyOKAlert] = try await SupabaseService.shared.client
                .from("alerts")
                .update(["is_read": true])
                .eq("id", value: alert.id.uuidString)
                .select()
                .execute()
                .value
            guard !updated.isEmpty else {
                errorMessage = String(localized: "Only the family owner can clear alerts.")
                return
            }

            alerts.removeAll { $0.id == alert.id }
            await AnalyticsService.shared.track(.alertDismissed, properties: ["type": alert.type])
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    private struct AcknowledgeAlertParams: Encodable {
        let p_alert_id: String
        let p_release: Bool
    }

    /// US-IOS013: acknowledge ("I've got this") or release a family alert. The
    /// resulting UPDATE streams to other caregivers through the existing
    /// `alerts` realtime subscription, so they see "Handled by <name>" without
    /// a manual refresh. The returned row is applied locally so the tapping
    /// caregiver gets instant feedback.
    ///
    /// Uses `acknowledge_alert_v2` (00055), which only claims an unclaimed
    /// alert and returns the row as it stands — so if someone else got there
    /// first, this caregiver sees "Handled by <them>" instead of silently
    /// overwriting the claim. Falls back to v1 on a backend without it.
    func acknowledgeAlert(_ alert: DailyOKAlert, release: Bool) async {
        // One claim / release at a time per alert (a double tap sent two RPCs).
        guard !acknowledgingAlertIds.contains(alert.id) else { return }
        acknowledgingAlertIds.insert(alert.id)
        defer { acknowledgingAlertIds.remove(alert.id) }
        let params = AcknowledgeAlertParams(p_alert_id: alert.id.uuidString, p_release: release)
        do {
            let updated: DailyOKAlert
            do {
                updated = try await SupabaseService.shared.client
                    .rpc("acknowledge_alert_v2", params: params)
                    .single()
                    .execute()
                    .value
            } catch let error where Self.isMissingRPC(error, named: "acknowledge_alert_v2") {
                // Only a backend without 00055 falls back to v1 (last writer
                // wins). Any other failure — offline, not authorized — must
                // NOT retry through v1, or a transient error would silently
                // overwrite another caregiver's claim.
                updated = try await SupabaseService.shared.client
                    .rpc("acknowledge_alert", params: params)
                    .single()
                    .execute()
                    .value
            }

            if let idx = alerts.firstIndex(where: { $0.id == updated.id }) {
                alerts[idx] = updated
            }
            let receiverName = receiverCards.first(where: { $0.id == alert.receiverId })?.name
            if !release, let currentUserId, let holder = updated.acknowledgedBy, holder != currentUserId {
                errorMessage = String(localized: "\(updated.acknowledgedByName ?? String(localized: "Another caregiver")) is already handling this.")
            } else if let outcome = Self.acknowledgementAnnouncement(release: release, receiverName: receiverName) {
                // Confirm it registered — the stand-down and check-on actions
                // already do; a claim was silent, including for VoiceOver.
                DailyOKHaptics.success()
                UIAccessibility.post(notification: .announcement, argument: outcome)
            }
            await AnalyticsService.shared.track(
                release ? .alertReleased : .alertAcknowledged,
                properties: ["type": alert.type]
            )
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    /// What VoiceOver hears after a claim or release went through.
    nonisolated static func acknowledgementAnnouncement(release: Bool, receiverName: String?) -> String? {
        if release {
            return String(localized: "Released. Other caregivers can take this on.")
        }
        if let receiverName {
            return String(localized: "You're handling this for \(receiverName). Other caregivers can see that.")
        }
        return String(localized: "You're handling this. Other caregivers can see that.")
    }

    /// PostgREST reports an unknown RPC as PGRST202 ("Could not find the
    /// function … in the schema cache"); older servers answer 404. Matched on
    /// the error's description so this doesn't depend on the SDK's error type.
    nonisolated static func isMissingRPC(_ error: Error, named name: String) -> Bool {
        let text = String(describing: error) + " " + error.localizedDescription
        return text.contains("PGRST202")
            || (text.contains(name) && (text.contains("Could not find") || text.contains("does not exist")))
    }

    // MARK: - Private

    /// US-IOS016: count care notes per receiver and apply to the cards' badges.
    /// Best-effort — a load failure (or an older backend without the table)
    /// simply leaves every badge at 0.
    private func applyNoteCounts(familyId: UUID) async {
        struct NoteReceiver: Decodable {
            let receiverId: UUID
            enum CodingKeys: String, CodingKey { case receiverId = "receiver_id" }
        }
        do {
            let rows: [NoteReceiver] = try await SupabaseService.shared.client
                .from("care_notes")
                .select("receiver_id")
                .eq("family_id", value: familyId.uuidString)
                .execute()
                .value
            var counts: [UUID: Int] = [:]
            for row in rows { counts[row.receiverId, default: 0] += 1 }
            for i in receiverCards.indices {
                receiverCards[i].noteCount = counts[receiverCards[i].id] ?? 0
            }
        } catch {
            // Non-critical; leave badges at 0.
        }
    }

    /// US-IOS017: mark receivers who have shared a passive "active today"
    /// signal for THEIR today. Keyed on `signal_date` in the receiver's zone,
    /// not the client-writable `updated_at`, so a stale or tampered row can't
    /// keep "Active today" beside a phone that has been dead for days.
    /// Best-effort and supplementary — failure leaves it nil.
    private func applyWellnessSignals(familyId: UUID) async {
        struct Signal: Decodable {
            let receiverId: UUID
            let active: Bool
            let signalDate: String
            enum CodingKeys: String, CodingKey {
                case receiverId = "receiver_id", active
                case signalDate = "signal_date"
            }
        }
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        // Any zone's "today" is on or after UTC yesterday.
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        let since = dayFormatter.string(from: Date().addingTimeInterval(-24 * 60 * 60))
        do {
            let rows: [Signal] = try await SupabaseService.shared.client
                .from("wellness_signals")
                .select("receiver_id, active, signal_date")
                .eq("family_id", value: familyId.uuidString)
                .gte("signal_date", value: since)
                .execute()
                .value
            for i in receiverCards.indices {
                let card = receiverCards[i]
                dayFormatter.timeZone = TimeZone(identifier: card.timezone ?? "") ?? .current
                let today = dayFormatter.string(from: Date())
                let todays = rows.filter { $0.receiverId == card.id && $0.signalDate == today }
                receiverCards[i].passiveActiveToday = todays.isEmpty ? nil : todays.contains { $0.active }
            }
        } catch {
            // Non-critical; leave as nil.
        }
    }

    private func loadAlerts(familyId: UUID) async {
        do {
            let loaded: [DailyOKAlert] = try await SupabaseService.shared.client
                .from("alerts")
                .select()
                .eq("family_id", value: familyId.uuidString)
                .eq("is_read", value: false)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value
            alerts = Self.sortAlerts(loaded)
        } catch {
            // Alerts are non-critical — but keep the last known list rather
            // than blanking an urgent alert on one failed refresh.
        }
    }

    private struct PushStatusParams: Encodable {
        let p_family_id: String
    }

    private struct PushStatusRow: Decodable {
        let userId: UUID
        let hasActiveToken: Bool
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case hasActiveToken = "has_active_token"
        }
    }

    /// Receivers with at least one active push token, via the
    /// `family_receiver_push_status` RPC (00055). Owners can't read other
    /// users' push_tokens rows (RLS), so the old direct SELECT always came back
    /// empty and every card warned "hasn't enabled notifications". nil =
    /// unknown (RPC missing or failed) — the card then shows no warning.
    private func activeNotificationUserIds(familyId: UUID) async -> Set<UUID>? {
        do {
            let rows: [PushStatusRow] = try await SupabaseService.shared.client
                .rpc("family_receiver_push_status", params: PushStatusParams(p_family_id: familyId.uuidString))
                .execute()
                .value
            return Set(rows.filter(\.hasActiveToken).map(\.userId))
        } catch {
            return nil
        }
    }

    /// Each receiver's settings (keyed by family_member_id) fetched in ONE query,
    /// so consistency can be judged against their real schedule.
    ///
    /// Owners read receiver_settings directly. Co-caregivers get 0 rows there
    /// (RLS — the row also holds home coordinates) without an error, so every
    /// card of theirs used to read "Pending" from midnight — on days off, while
    /// paused, before the due time — with every day counted as expected and
    /// "Escalation is off" never known. Any member the direct read didn't
    /// return is filled from `family_receiver_schedules` (00057), which
    /// returns the schedule fields to the owner and active co-caregivers.
    /// Missing from both (older server, offline) stays absent: "unknown".
    private func receiverSettingsByMember(memberIds: [UUID], familyId: UUID) async -> [UUID: ReceiverSettings] {
        guard !memberIds.isEmpty else { return [:] }
        let direct: [ReceiverSettings] = (try? await SupabaseService.shared.client
            .from("receiver_settings")
            .select()
            .in("family_member_id", values: memberIds.map { $0.uuidString })
            .execute()
            .value) ?? []
        var fallback: [ReceiverSettings]?
        if Self.needsScheduleFallback(direct: direct, memberIds: memberIds) {
            fallback = try? await CheckInService.shared.familyReceiverSchedules(familyId: familyId)
        }
        return Self.mergeSchedules(direct: direct, fallback: fallback, memberIds: memberIds)
    }

    /// The direct read left someone out (always, for a co-caregiver).
    nonisolated static func needsScheduleFallback(direct: [ReceiverSettings], memberIds: [UUID]) -> Bool {
        !Set(memberIds).isSubset(of: Set(direct.map(\.familyMemberId)))
    }

    /// Direct rows win; the RPC fills only members the direct read missed, and
    /// only the members asked for (the RPC returns the whole family).
    nonisolated static func mergeSchedules(
        direct: [ReceiverSettings],
        fallback: [ReceiverSettings]?,
        memberIds: [UUID]
    ) -> [UUID: ReceiverSettings] {
        let wanted = Set(memberIds)
        var result: [UUID: ReceiverSettings] = [:]
        for row in (fallback ?? []) where wanted.contains(row.familyMemberId) {
            result[row.familyMemberId] = row
        }
        for row in direct where wanted.contains(row.familyMemberId) {
            result[row.familyMemberId] = row
        }
        return result
    }

    private func computeWeeklySummary(
        checkIns: [CheckIn],
        totalScheduledDays: Int,
        totalCheckedInDays: Int,
        avgCheckInMinutes: Int?,
        lagging: [String]
    ) -> WeeklySummary {
        // Schedule-aware: the denominator is the days receivers were actually
        // scheduled to check in this week (summed across receivers), not a flat
        // receivers × 7. The "X/Y" bubble shows checked-in days / scheduled days.
        // Nothing scheduled → 0 with `hasData == false` (rendered "—"), never a
        // reassuring 100%.
        let totalExpected = totalScheduledDays
        let totalCheckIns = totalCheckedInDays
        let consistency = totalExpected > 0 ? min(100.0, Double(totalCheckIns) / Double(totalExpected) * 100) : 0

        // Average check-in time — minute-of-day already accumulated in each
        // receiver's own timezone (US-IOS059/075), so the figure isn't skewed by
        // the owner's device zone.
        let avgTime: String
        if let avgMinutes = avgCheckInMinutes {
            let hour = avgMinutes / 60
            let minute = avgMinutes % 60
            // Locale-aware short time (12h in en_US, 24h in e.g. fr_FR) — US-IOS044.
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            if let date = Calendar.current.date(from: components) {
                avgTime = formatter.string(from: date)
            } else {
                avgTime = "--"
            }
        } else {
            avgTime = "--"
        }

        // Mood breakdown — exclude unrecognized server moods so they don't skew
        // the wellness analytics (US-IOS101).
        var moodBreakdown: [Mood: Int] = [:]
        for checkIn in checkIns {
            if let mood = checkIn.mood, mood != .unknown {
                moodBreakdown[mood, default: 0] += 1
            }
        }

        return WeeklySummary(
            consistencyPercentage: consistency,
            averageCheckInTime: avgTime,
            totalCheckIns: totalCheckIns,
            totalExpected: totalExpected,
            moodBreakdown: moodBreakdown,
            lagging: lagging
        )
    }

    /// Subscribe to realtime changes on the three tables that drive the owner UI:
    ///   - `checkins`          — new "I'm OK" responses flip Pending → Checked In
    ///   - `checkin_requests`  — status transitions (pending → checked_in / missed)
    ///   - `alerts`            — urgent / pattern alerts show in the banner
    ///
    /// The subscription is gated by `family_id` so each owner only receives their
    /// own family's events. Duplicate reloads are debounced (250 ms) so a burst of
    /// events (e.g. edge function inserts a checkin AND updates the request row)
    /// triggers a single refresh.
    private func subscribeToRealtime(familyId: UUID) async {
        // Skip if we're already subscribed to this family
        if realtimeFamilyId == familyId, realtimeChannel != nil {
            return
        }

        // Tear down any prior subscription (family switch, sign-out/sign-in, etc.)
        await teardownRealtime()

        let client = SupabaseService.shared.client
        // A unique topic per subscription: the realtime client hands back an
        // EXISTING channel for a known topic, and a channel left subscribed by
        // a previous dashboard (sign-out → sign-in, role change) returns
        // streams that never fire — the dashboard silently stopped updating.
        let channel = client.realtimeV2.channel("owner-dashboard:\(familyId.uuidString):\(UUID().uuidString)")

        let checkinChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "checkins",
            filter: "family_id=eq.\(familyId.uuidString)"
        )

        let requestChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "checkin_requests",
            filter: "family_id=eq.\(familyId.uuidString)"
        )

        let alertChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "alerts",
            filter: "family_id=eq.\(familyId.uuidString)"
        )

        await channel.subscribe()

        realtimeListenerTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await _ in checkinChanges { await self?.scheduleRefresh() }
                }
                group.addTask { [weak self] in
                    for await _ in requestChanges { await self?.scheduleRefresh() }
                }
                group.addTask { [weak self] in
                    for await _ in alertChanges { await self?.scheduleRefresh() }
                }
            }
        }

        realtimeChannel = channel
        realtimeFamilyId = familyId
    }

    /// Debounced reload — coalesces bursts of realtime events into one reload.
    private func scheduleRefresh() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000) // 250 ms
            guard !Task.isCancelled else { return }
            await self?.loadDashboard()
        }
    }

    private func teardownRealtime() async {
        realtimeListenerTask?.cancel()
        realtimeListenerTask = nil
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        if let channel = realtimeChannel {
            await channel.unsubscribe()
        }
        realtimeChannel = nil
        realtimeFamilyId = nil
    }
}
