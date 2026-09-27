import Foundation

// MARK: - History day model
//
// Pure, unit-tested classification behind the History tab: the heatmap, the
// summary card, the per-day log and the exported PDF all read from this one
// model, so they can't disagree with each other — or with the dashboard, whose
// rules (help requests outrank everything, a request is answered by a later
// check-in, a stood-down request is "reached another way") are reused here.
//
// Past days are judged from what actually happened — the day's
// `checkin_requests` and `checkins` rows — not from today's settings. Before
// this, a pause set today erased every earlier miss, and a schedule change
// repainted months of history. The current settings are only used for TODAY
// (is the check-in due yet?) and as a fallback when the requests can't be read.

/// What one receiver-local day shows in History.
enum HistoryDayStatus: Equatable, Sendable {
    /// Nothing was asked and nothing happened: an off day, a paused day, a day
    /// before they joined, or (without a schedule) simply no check-in.
    case notAsked
    /// Checked in before the family was alerted.
    case onTime
    /// Checked in, but only after the family had been alerted (or after the
    /// request was marked missed).
    case late
    /// A check-in was asked for and not answered that day.
    case missed
    /// Not answered, but a caregiver stopped the alerts ("I've reached them").
    case stoodDown
    /// A check-in that day asked for help (need help / call me / kid SOS).
    /// Outranks everything else, as on the dashboard.
    case needsHelp
    /// Today, before the check-in is due. Carries the due time when known.
    case dueLater(Date?)
    /// Asked and not answered yet, still inside the escalation window
    /// (today's request, or last night's that is still pending).
    case waiting

    /// A day something was expected or happened — counted in the summary.
    /// Today's in-progress states are not: an evening check-in can't count
    /// against someone at 9 AM.
    var isResolved: Bool {
        switch self {
        case .onTime, .late, .missed, .stoodDown, .needsHelp: return true
        case .notAsked, .dueLater, .waiting: return false
        }
    }

    /// Resolved days that count as "checked in".
    var isAnswered: Bool {
        switch self {
        case .onTime, .late, .needsHelp: return true
        default: return false
        }
    }
}

/// One thing that happened on a day, for the log, the day detail and the PDF.
struct HistoryEvent: Identifiable, Sendable {
    enum Kind: Sendable {
        /// A check-in. `help` is set for need help / call me / SOS;
        /// `afterAlert` when it answered a request the family had already
        /// been alerted about.
        case checkIn(CheckIn, help: HelpKind?, afterAlert: Bool)
        /// A request that wasn't answered that day. `live` = still pending
        /// and not yet expired; `alerted` = the family was alerted (step 2+ or
        /// missed).
        case unanswered(CheckInRequest, alerted: Bool, live: Bool)
        /// A caregiver stopped the alerts for that request.
        case stoodDown(CheckInRequest)
    }

    let id: String
    let at: Date
    let kind: Kind
}

struct HistoryDay: Identifiable, Sendable {
    /// Start of the day in the receiver's calendar.
    let date: Date
    let status: HistoryDayStatus
    let checkIns: [CheckIn]
    let events: [HistoryEvent]
    let isToday: Bool

    var id: Date { date }

    var helpKind: HelpKind? {
        checkIns.lazy.compactMap { DashboardViewModel.helpKind(for: $0) }.first
    }
}

struct HistoryStats: Equatable, Sendable {
    /// Days a check-in was asked for (or one happened), excluding today while
    /// it's still in progress.
    var expectedDays = 0
    var answeredDays = 0
    var onTimeDays = 0
    var lateDays = 0
    var missedDays = 0
    var stoodDownDays = 0
    /// Individual help check-ins (a day can have more than one).
    var helpRequests = 0
    var totalCheckIns = 0

    /// nil when nothing was expected — never a reassuring 100% for "no data".
    var percent: Int? {
        guard expectedDays > 0 else { return nil }
        return Int((Double(answeredDays) / Double(expectedDays) * 100).rounded())
    }
}

enum HistoryTimeline {

    /// The window History shows: exactly `days` receiver-local days ending
    /// today — the same window the heatmap draws and the PDF prints.
    static func window(days: Int, now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return (start, end)
    }

    /// Check-ins dated after `now` can't be real (the server clamps its own
    /// writes; a hand-crafted row isn't evidence of anything). A few minutes of
    /// slack covers clock skew between this device and the server.
    static let futureTolerance: TimeInterval = 5 * 60

    /// Build every day in the window, oldest first.
    ///
    /// - Parameters:
    ///   - requests: the window's `checkin_requests`, or nil when they couldn't
    ///     be read — the days are then estimated from `settings`.
    ///   - settings: the receiver's CURRENT settings; used for today, and for
    ///     past days only when `requests` is nil. nil = unknown schedule, in
    ///     which case nothing is ever painted missed by guesswork.
    static func build(
        checkIns: [CheckIn],
        requests: [CheckInRequest]?,
        settings: ReceiverSettings?,
        enrolledSince: Date?,
        days: Int,
        now: Date = Date(),
        calendar: Calendar
    ) -> [HistoryDay] {
        let (start, end) = Self.window(days: days, now: now, calendar: calendar)
        let latestPlausible = now.addingTimeInterval(futureTolerance)
        let inWindow = checkIns.filter {
            $0.checkedInAt >= start && $0.checkedInAt < end && $0.checkedInAt <= latestPlausible
        }
        let checkInsByDay = Dictionary(grouping: inWindow) { calendar.startOfDay(for: $0.checkedInAt) }
        let requestsByDay: [Date: [CheckInRequest]]? = requests.map { all in
            Dictionary(grouping: all.filter { $0.createdAt >= start && $0.createdAt < end }) {
                calendar.startOfDay(for: $0.createdAt)
            }
        }
        let enrolledDay = enrolledSince.map { calendar.startOfDay(for: $0) }
        let today = calendar.startOfDay(for: now)

        var result: [HistoryDay] = []
        var day = start
        while day < end {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let dayCheckIns = (checkInsByDay[day] ?? []).sorted { $0.checkedInAt < $1.checkedInAt }
            let dayRequests: [CheckInRequest]? = requestsByDay.map { byDay in
                (byDay[day] ?? []).sorted { $0.createdAt < $1.createdAt }
            }
            let isToday = day == today

            let status = classify(
                day: day, dayEnd: dayEnd, isToday: isToday,
                checkIns: dayCheckIns, requests: dayRequests,
                settings: settings, enrolledDay: enrolledDay,
                now: now, calendar: calendar
            )
            let dayEvents = Self.events(
                checkIns: dayCheckIns, requests: dayRequests, dayEnd: dayEnd,
                now: now, status: status
            )
            result.append(HistoryDay(date: day, status: status, checkIns: dayCheckIns, events: dayEvents, isToday: isToday))
            day = dayEnd
        }
        return result
    }

    // MARK: Classification

    static func classify(
        day: Date,
        dayEnd: Date,
        isToday: Bool,
        checkIns: [CheckIn],
        requests: [CheckInRequest]?,
        settings: ReceiverSettings?,
        enrolledDay: Date?,
        now: Date,
        calendar: Calendar
    ) -> HistoryDayStatus {
        // A help request is never reassurance (dashboard rule, c73cbf1).
        if checkIns.contains(where: { DashboardViewModel.helpKind(for: $0) != nil }) {
            return .needsHelp
        }

        if let requests {
            let open = requests.filter { !isAnswered($0, checkIns: checkIns, dayEnd: dayEnd) }
            if !open.isEmpty {
                let notStoodDown = open.filter { !isStoodDown($0) }
                if notStoodDown.isEmpty { return .stoodDown }
                // Still escalating (today's, or last night's that hasn't run
                // its course yet): the dashboard shows it as pending, so this
                // day isn't "Missed" until the server says so.
                if notStoodDown.allSatisfy({ isLive($0, now: now) }) { return .waiting }
                return .missed
            }
            if !checkIns.isEmpty {
                let answeredAfterAlert = requests.contains { alertedBeforeAnswer($0) }
                return answeredAfterAlert ? .late : .onTime
            }
            if isToday { return todayWithNothingYet(settings: settings, now: now, calendar: calendar) }
            // Nothing was asked that day — off day, paused, or not yet joined.
            return .notAsked
        }

        // Requests unavailable: estimate from the schedule, as History always
        // used to — but never from an invented 8:00 AM default.
        if let first = checkIns.first {
            guard let settings,
                  let slot = slotTimes(settings: settings, day: day, calendar: calendar).first else {
                return .onTime
            }
            let alertOffset = settings.gracePeriodMinutes + settings.reminderIntervalMinutes
            return first.checkedInAt > slot.addingTimeInterval(TimeInterval(alertOffset * 60)) ? .late : .onTime
        }
        if let enrolledDay, day < enrolledDay { return .notAsked }
        if isToday {
            let state = todayWithNothingYet(settings: settings, now: now, calendar: calendar)
            guard state == .waiting, let settings,
                  case .due(let at) = DashboardViewModel.scheduleState(settings: settings, now: now, calendar: calendar) else {
                return state
            }
            // Past the whole escalation window with no answer → missed.
            let missedAfter = settings.gracePeriodMinutes + 3 * settings.reminderIntervalMinutes
            return now > at.addingTimeInterval(TimeInterval(missedAfter * 60)) ? .missed : .waiting
        }
        guard let settings else { return .notAsked }
        // The CURRENT pause is not applied to the past: it says nothing about
        // what was asked last month.
        return slotTimes(settings: settings, day: day, calendar: calendar).isEmpty ? .notAsked : .missed
    }

    /// Today, with no check-in and no request yet.
    static func todayWithNothingYet(settings: ReceiverSettings?, now: Date, calendar: Calendar) -> HistoryDayStatus {
        switch DashboardViewModel.scheduleState(settings: settings, now: now, calendar: calendar) {
        case .notYetDue(let at): return .dueLater(at)
        case .due: return .waiting
        case .paused, .offToday: return .notAsked
        case .unknown: return .dueLater(nil)
        }
    }

    /// Answered on its own day: a check-in at or after the ask, before the
    /// day ended — or the server closed it that day.
    static func isAnswered(_ request: CheckInRequest, checkIns: [CheckIn], dayEnd: Date) -> Bool {
        if checkIns.contains(where: { $0.checkedInAt >= request.createdAt && $0.checkedInAt < dayEnd }) {
            return true
        }
        if request.status == .checkedIn {
            return request.respondedAt.map { $0 < dayEnd } ?? true
        }
        return false
    }

    /// A request still in play: pending and inside the 24 hours before
    /// expire_old_requests closes it. A pending row older than that is a
    /// request nobody answered (escalation off, or it outlived its chain).
    static func isLive(_ request: CheckInRequest, now: Date) -> Bool {
        request.status == .pending && now < request.createdAt.addingTimeInterval(24 * 60 * 60)
    }

    /// The family had been alerted before this request was answered:
    /// escalation reached step 2 (owner alerted) or the request was marked
    /// missed. escalation_step is kept when a check-in closes the request.
    static func alertedBeforeAnswer(_ request: CheckInRequest) -> Bool {
        request.escalationStep >= 2 || request.status == .missed
    }

    /// The dashboard's stand-down rule (DashboardViewModel.resolveStatus),
    /// extended to expired rows: recorded by the server (00055), or inferred
    /// from a cleared escalation clock on a request that had started
    /// escalating. A pending request with a stand-down record but a live clock
    /// was re-armed since, so it isn't stood down.
    static func isStoodDown(_ request: CheckInRequest) -> Bool {
        if request.stoodDownAt != nil {
            return request.status == .missed || request.status == .expired || request.nextEscalationAt == nil
        }
        return (request.status == .pending || request.status == .expired)
            && request.escalationStep >= 1
            && request.nextEscalationAt == nil
    }

    /// Every scheduled time on `day`, ignoring the pause flag.
    static func slotTimes(settings: ReceiverSettings, day: Date, calendar: Calendar) -> [Date] {
        ReceiverViewModel.scheduledTimes(for: settings, on: day, calendar: calendar).compactMap { (raw: String) -> Date? in
            guard let (hour, minute) = ReceiverViewModel.parseCheckinTime(raw) else { return nil }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            return calendar.date(from: comps)
        }.sorted()
    }

    // MARK: Events

    static func events(
        checkIns: [CheckIn],
        requests: [CheckInRequest]?,
        dayEnd: Date,
        now: Date,
        status: HistoryDayStatus
    ) -> [HistoryEvent] {
        var events: [HistoryEvent] = []
        var afterAlertIds = Set<UUID>()

        if let requests {
            for request in requests {
                if isAnswered(request, checkIns: checkIns, dayEnd: dayEnd) {
                    // The check-in that answered it: the first one after the ask.
                    if alertedBeforeAnswer(request),
                       let answer = checkIns.first(where: { $0.checkedInAt >= request.createdAt }) {
                        afterAlertIds.insert(answer.id)
                    }
                    continue
                }
                if isStoodDown(request) {
                    events.append(HistoryEvent(
                        id: "rq-\(request.id)", at: request.createdAt,
                        kind: .unanswered(request, alerted: alertedBeforeAnswer(request), live: false)
                    ))
                    events.append(HistoryEvent(
                        id: "sd-\(request.id)", at: request.stoodDownAt ?? request.createdAt,
                        kind: .stoodDown(request)
                    ))
                } else {
                    let live = isLive(request, now: now)
                    events.append(HistoryEvent(
                        id: "rq-\(request.id)", at: request.createdAt,
                        kind: .unanswered(request, alerted: alertedBeforeAnswer(request), live: live)
                    ))
                }
            }
        } else if status == .late, let first = checkIns.first {
            afterAlertIds.insert(first.id)
        }

        for checkIn in checkIns {
            events.append(HistoryEvent(
                id: "ci-\(checkIn.id)", at: checkIn.checkedInAt,
                kind: .checkIn(
                    checkIn,
                    help: DashboardViewModel.helpKind(for: checkIn),
                    afterAlert: afterAlertIds.contains(checkIn.id)
                )
            ))
        }
        return events.sorted { $0.at < $1.at }
    }

    // MARK: Summary

    static func stats(for days: [HistoryDay]) -> HistoryStats {
        var stats = HistoryStats()
        for day in days {
            stats.totalCheckIns += day.checkIns.count
            stats.helpRequests += day.checkIns.filter { DashboardViewModel.helpKind(for: $0) != nil }.count
            guard day.status.isResolved else { continue }
            stats.expectedDays += 1
            if day.status.isAnswered { stats.answeredDays += 1 }
            switch day.status {
            case .onTime: stats.onTimeDays += 1
            case .late: stats.lateDays += 1
            case .missed: stats.missedDays += 1
            case .stoodDown: stats.stoodDownDays += 1
            default: break
            }
        }
        return stats
    }

    /// The dashboard computes its streak from the last 30 days of check-ins
    /// (`checkInHistory(days: 30)`), so the same lookback applies here — a
    /// 90-day History window would otherwise print a longer streak than the
    /// dashboard card for the same person.
    static let streakLookbackDays = 30

    /// The dashboard's streak rule (Streaks.currentStreak: today counts once
    /// done; a not-yet-done today doesn't zero it), so History, the PDF and the
    /// dashboard card print the same number.
    static func currentStreak(checkIns: [CheckIn], now: Date, calendar: Calendar) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let latestPlausible = now.addingTimeInterval(futureTolerance)
        let earliest = calendar.date(byAdding: .day, value: -streakLookbackDays, to: now)
            ?? now.addingTimeInterval(-Double(streakLookbackDays) * 86_400)
        let iso = checkIns
            .filter { $0.checkedInAt >= earliest && $0.checkedInAt <= latestPlausible }
            .map { formatter.string(from: $0.checkedInAt) }
        return Streaks.currentStreak(isoTimestamps: iso, calendar: calendar, today: now)
    }

    // MARK: Wording (shared by the screen and the PDF)

    static func label(for status: HistoryDayStatus, help: HelpKind?, timezone: String?) -> String {
        switch status {
        case .notAsked: return "No check-in asked"
        case .onTime: return "Checked in"
        case .late: return "Checked in after an alert"
        case .missed: return "Missed"
        case .stoodDown: return "Missed · reached another way"
        case .needsHelp: return help?.label ?? HelpKind.needHelp.label
        case .dueLater(let at):
            guard let at else { return "Nothing yet today" }
            return "Due at \(ReceiverTime.format(at, timezone: timezone))"
        case .waiting: return "Waiting for an answer"
        }
    }

    static func title(for event: HistoryEvent) -> String {
        switch event.kind {
        case .checkIn(_, let help, let afterAlert):
            if let help { return help.label }
            return afterAlert ? "Checked in after the family was alerted" : "Checked in"
        case .unanswered(let request, let alerted, let live):
            let what = request.type == .onDemand ? "Requested check-in" : "Check-in"
            if live { return "\(what) asked · no answer yet" }
            return alerted ? "\(what) not answered · family alerted" : "\(what) not answered"
        case .stoodDown:
            return "Alerts stopped · reached another way"
        }
    }

    /// Secondary line for a check-in: how it arrived, mood, kid reply, place.
    static func detail(for event: HistoryEvent) -> String? {
        guard case .checkIn(let checkIn, let help, _) = event.kind else { return nil }
        var parts: [String] = []
        if let mood = checkIn.mood, mood != .unknown { parts.append("Mood: \(mood.label)") }
        if help != .sos, let raw = checkIn.kidResponseType, let kid = KidResponseType(rawValue: raw) {
            parts.append(kid.label)
        }
        if let raw = checkIn.locationLabel, let place = LocationLabel(rawValue: raw) {
            parts.append("At \(place.label)")
        }
        parts.append(sourceLabel(checkIn.source))
        return parts.joined(separator: " · ")
    }

    /// Plain words for how a check-in arrived — never a raw enum value.
    static func sourceLabel(_ source: CheckInSource) -> String {
        switch source {
        case .app: return "In the app"
        case .notification, .needHelp, .callMe: return "From the notification"
        case .onDemand: return "Answered your request"
        case .widget: return "From the widget"
        case .control: return "From Control Center"
        case .siri: return "With Siri"
        }
    }
}
