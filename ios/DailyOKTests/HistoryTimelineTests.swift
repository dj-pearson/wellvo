import XCTest
@testable import DailyOK

/// The History tab's day model. Every section of History (calendar, summary,
/// log, PDF) reads it, so these rules are what keep History from contradicting
/// the dashboard: help requests are never green, today is never "missed"
/// before it's due, a stood-down miss says so, and today's settings don't
/// rewrite the past.
final class HistoryTimelineTests: XCTestCase {

    // 2026-09-27 15:00 UTC, a Sunday. Window of 7 days: Sep 21 … Sep 27.
    private let now = HistoryTimelineTests.date("2026-09-27T15:00:00Z")

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func date(_ iso: String) -> Date { Self.date(iso) }

    private func checkIn(
        _ iso: String,
        response: CheckInResponseType? = nil,
        kid: String? = nil,
        mood: Mood? = nil,
        source: CheckInSource = .notification
    ) -> CheckIn {
        CheckIn(
            id: UUID(), receiverId: UUID(), familyId: UUID(),
            checkedInAt: date(iso), mood: mood, source: source,
            responseType: response, kidResponseType: kid
        )
    }

    private func request(
        _ iso: String,
        status: CheckInRequestStatus,
        step: Int = 0,
        type: CheckInRequestType = .scheduled,
        next: Date? = nil,
        respondedAt: Date? = nil,
        stoodDownAt: Date? = nil
    ) -> CheckInRequest {
        var request = CheckInRequest(
            id: UUID(), familyId: UUID(), receiverId: UUID(), requestedBy: UUID(),
            type: type, status: status, createdAt: date(iso),
            respondedAt: respondedAt, escalationStep: step, nextEscalationAt: next
        )
        request.stoodDownAt = stoodDownAt
        return request
    }

    /// ReceiverSettings only has a Decodable init.
    private func settings(
        checkinTime: String = "09:00",
        scheduleType: String = "daily",
        paused: Bool = false,
        customSchedule: [String: String]? = nil
    ) -> ReceiverSettings {
        var dict: [String: Any] = [
            "id": UUID().uuidString,
            "family_member_id": UUID().uuidString,
            "checkin_time": checkinTime,
            "timezone": "UTC",
            "grace_period_minutes": 30,
            "reminder_interval_minutes": 15,
            "escalation_enabled": true,
            "mood_tracking_enabled": false,
            "sms_escalation_enabled": false,
            "is_active": true,
            "location_tracking_enabled": false,
            "geofence_radius_meters": 100,
            "location_alert_enabled": false,
            "schedule_type": scheduleType,
            "schedule_paused": paused,
        ]
        if let customSchedule { dict["custom_schedule"] = customSchedule }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(ReceiverSettings.self, from: data)
    }

    private func build(
        checkIns: [CheckIn] = [],
        requests: [CheckInRequest]? = [],
        settings: ReceiverSettings? = nil,
        enrolledSince: Date? = nil,
        days: Int = 7,
        now: Date? = nil
    ) -> [HistoryDay] {
        HistoryTimeline.build(
            checkIns: checkIns, requests: requests, settings: settings,
            enrolledSince: enrolledSince, days: days, now: now ?? self.now, calendar: utc
        )
    }

    private func day(_ days: [HistoryDay], _ isoDay: String) -> HistoryDay {
        let target = date("\(isoDay)T00:00:00Z")
        return days.first { $0.date == target }!
    }

    // MARK: - Window

    func testWindowIsExactlyTheRequestedDaysEndingToday() {
        let days = build(days: 30)
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.first?.date, date("2026-08-29T00:00:00Z"))
        XCTAssertEqual(days.last?.date, date("2026-09-27T00:00:00Z"))
        XCTAssertTrue(days.last!.isToday)
    }

    /// Future-dated rows (e.g. inserted by hand) are not evidence of a check-in.
    func testFutureAndOutOfWindowCheckInsAreIgnored() {
        let days = build(checkIns: [
            checkIn("2026-09-20T09:00:00Z"),      // day before the window
            checkIn("2026-09-27T18:00:00Z"),      // later today than `now`
        ])
        XCTAssertTrue(days.allSatisfy { $0.checkIns.isEmpty })
    }

    // MARK: - Help requests

    /// The dashboard shows Needs Help for these; History used to paint the
    /// day green "On time" and list it as an ordinary check-in.
    func testHelpRequestsAreNeverOnTime() {
        let days = build(
            checkIns: [
                checkIn("2026-09-22T09:04:00Z", response: .needHelp),
                checkIn("2026-09-23T09:04:00Z", response: .callMe),
                checkIn("2026-09-24T16:10:00Z", kid: "sos"),
            ],
            requests: [
                request("2026-09-22T09:00:00Z", status: .checkedIn),
                request("2026-09-23T09:00:00Z", status: .checkedIn),
            ]
        )
        XCTAssertEqual(day(days, "2026-09-22").status, .needsHelp)
        XCTAssertEqual(day(days, "2026-09-22").helpKind, .needHelp)
        XCTAssertEqual(day(days, "2026-09-23").helpKind, .callMe)
        XCTAssertEqual(day(days, "2026-09-24").status, .needsHelp)
        XCTAssertEqual(day(days, "2026-09-24").helpKind, .sos)

        let event = day(days, "2026-09-22").events.first!
        XCTAssertEqual(HistoryTimeline.title(for: event), "Asked for help")

        XCTAssertEqual(HistoryTimeline.stats(for: days).helpRequests, 3)
    }

    // MARK: - Today

    /// 7 AM, check-in due at 9: today is "due later", not red "Missed".
    func testTodayBeforeTheCheckInIsDueIsNotMissed() {
        let early = date("2026-09-27T07:00:00Z")
        let days = build(settings: settings(checkinTime: "09:00"), now: early)
        XCTAssertEqual(days.last?.status, .dueLater(date("2026-09-27T09:00:00Z")))
        XCTAssertEqual(HistoryTimeline.stats(for: days).expectedDays, 0)
    }

    func testTodayWithAnOpenRequestIsWaiting() {
        let days = build(
            requests: [request("2026-09-27T09:00:00Z", status: .pending, step: 1, next: date("2026-09-27T16:00:00Z"))],
            settings: settings()
        )
        XCTAssertEqual(days.last?.status, .waiting)
        // In progress: not counted against them yet.
        XCTAssertEqual(HistoryTimeline.stats(for: days).expectedDays, 0)
    }

    /// Without the requests and without a schedule, today is never guessed
    /// to be missed.
    func testTodayWithoutAScheduleIsNeutral() {
        let days = build(requests: nil, settings: nil)
        XCTAssertEqual(days.last?.status, .dueLater(nil))
    }

    // MARK: - Past days from requests

    func testUnansweredRequestIsMissed() {
        let days = build(requests: [request("2026-09-25T09:00:00Z", status: .missed, step: 3)])
        XCTAssertEqual(day(days, "2026-09-25").status, .missed)
        let event = day(days, "2026-09-25").events.first!
        XCTAssertEqual(HistoryTimeline.title(for: event), "Check-in not answered · family alerted")
    }

    /// Missed, then a check-in later that day: they answered, after alerts.
    func testMissedThenCheckedInLaterThatDayIsLate() {
        let late = checkIn("2026-09-25T11:30:00Z")
        let days = build(
            checkIns: [late],
            requests: [request("2026-09-25T09:00:00Z", status: .missed, step: 3)]
        )
        XCTAssertEqual(day(days, "2026-09-25").status, .late)
        guard case .checkIn(_, _, let afterAlert) = day(days, "2026-09-25").events.last!.kind else {
            return XCTFail("expected the check-in event")
        }
        XCTAssertTrue(afterAlert)
    }

    /// escalation_step survives the check-in that closes a request: step 2
    /// means the owner had already been alerted.
    func testAnsweredAfterTheOwnerWasAlertedIsLate() {
        let days = build(
            checkIns: [checkIn("2026-09-24T10:05:00Z"), checkIn("2026-09-25T09:40:00Z")],
            requests: [
                request("2026-09-24T09:00:00Z", status: .checkedIn, step: 2),
                request("2026-09-25T09:00:00Z", status: .checkedIn, step: 1),
            ]
        )
        XCTAssertEqual(day(days, "2026-09-24").status, .late)
        XCTAssertEqual(day(days, "2026-09-25").status, .onTime, "A reminder to the receiver alone isn't an alert")
    }

    func testStoodDownMissIsReachedAnotherWay() {
        let days = build(requests: [
            request("2026-09-23T09:00:00Z", status: .missed, step: 3,
                    next: date("2026-09-23T10:00:00Z"), stoodDownAt: date("2026-09-23T10:12:00Z")),
        ])
        let stood = day(days, "2026-09-23")
        XCTAssertEqual(stood.status, .stoodDown)
        XCTAssertTrue(stood.events.contains { if case .stoodDown = $0.kind { return true } else { return false } })
        let stats = HistoryTimeline.stats(for: days)
        XCTAssertEqual(stats.stoodDownDays, 1)
        XCTAssertEqual(stats.missedDays, 0)
    }

    /// Older backend without stood_down_at: a stepped request whose clock was
    /// cleared (cancel-escalation) and then expired.
    func testInferredStandDownOnExpiredRequest() {
        let days = build(requests: [request("2026-09-23T09:00:00Z", status: .expired, step: 2, next: nil)])
        XCTAssertEqual(day(days, "2026-09-23").status, .stoodDown)
    }

    /// Dashboard rule: a stand-down record on a PENDING request with a live
    /// clock was re-armed since (snooze / undo) — it's escalating again.
    func testReArmedPendingRequestIsNotStoodDown() {
        let rearmed = request("2026-09-27T09:00:00Z", status: .pending, step: 1,
                              next: date("2026-09-27T15:30:00Z"), stoodDownAt: date("2026-09-27T09:40:00Z"))
        XCTAssertFalse(HistoryTimeline.isStoodDown(rearmed))
        XCTAssertEqual(build(requests: [rearmed], settings: settings()).last?.status, .waiting)
    }

    /// Last night's 9 PM request is still escalating at 7 AM: the dashboard
    /// shows it as pending, so History must not already call yesterday Missed.
    func testLastNightsStillPendingRequestIsWaitingNotMissed() {
        let early = date("2026-09-27T07:00:00Z")
        let days = build(
            requests: [request("2026-09-26T21:00:00Z", status: .pending, step: 1, next: date("2026-09-27T07:15:00Z"))],
            settings: settings(),
            now: early
        )
        XCTAssertEqual(day(days, "2026-09-26").status, .waiting)
        XCTAssertEqual(HistoryTimeline.stats(for: days).missedDays, 0)
        // A pending row past its 24 hours is a request nobody answered.
        let stale = build(requests: [request("2026-09-25T06:00:00Z", status: .pending, step: 0, next: date("2026-09-25T06:30:00Z"))])
        XCTAssertEqual(day(stale, "2026-09-25").status, .missed)
    }

    /// A 3 PM "check on Mom" nobody answered, on a day she checked in at 8:
    /// the dashboard showed it — History must too.
    func testUnansweredOnDemandAfterAMorningCheckInIsMissed() {
        let days = build(
            checkIns: [checkIn("2026-09-24T08:05:00Z")],
            requests: [
                request("2026-09-24T08:00:00Z", status: .checkedIn),
                request("2026-09-24T15:00:00Z", status: .expired, type: .onDemand),
            ]
        )
        XCTAssertEqual(day(days, "2026-09-24").status, .missed)
        let titles = day(days, "2026-09-24").events.map(HistoryTimeline.title(for:))
        XCTAssertEqual(titles, ["Checked in", "Requested check-in not answered"])
    }

    /// Answered the next morning: that day still went unanswered.
    func testRequestAnsweredOnTheNextDayIsMissedOnItsDay() {
        let days = build(
            checkIns: [checkIn("2026-09-25T08:00:00Z")],
            requests: [request("2026-09-24T20:00:00Z", status: .checkedIn, step: 3,
                               respondedAt: date("2026-09-25T08:00:00Z"))]
        )
        XCTAssertEqual(day(days, "2026-09-24").status, .missed)
        XCTAssertEqual(day(days, "2026-09-25").status, .onTime)
    }

    /// Nothing asked that day → nothing missed, whatever the schedule says now.
    func testPastDayWithNoRequestIsNotAsked() {
        let days = build(requests: [], settings: settings())
        XCTAssertEqual(day(days, "2026-09-22").status, .notAsked)
    }

    /// Pausing today must not erase last week's misses (it used to: the
    /// current pause emptied the scheduled weekdays for the whole window).
    func testTodaysPauseDoesNotEraseEarlierMisses() {
        let days = build(
            requests: [request("2026-09-22T09:00:00Z", status: .missed, step: 3)],
            settings: settings(paused: true)
        )
        XCTAssertEqual(day(days, "2026-09-22").status, .missed)
        XCTAssertEqual(days.last?.status, .notAsked, "Paused today: nothing due")
    }

    // MARK: - Fallback without requests

    func testFallbackDoesNotApplyTheCurrentPauseToThePast() {
        let days = build(requests: nil, settings: settings(paused: true))
        XCTAssertEqual(day(days, "2026-09-22").status, .missed)
    }

    func testFallbackWithoutAScheduleNeverPaintsMissed() {
        let days = build(requests: nil, settings: nil)
        XCTAssertTrue(days.filter { !$0.isToday }.allSatisfy { $0.status == .notAsked })
    }

    func testFallbackHonoursOffDays() {
        // Weekdays only: Sat Sep 26 is off.
        let weekdays = settings(scheduleType: "custom", customSchedule: [
            "mon": "09:00", "tue": "09:00", "wed": "09:00", "thu": "09:00", "fri": "09:00",
        ])
        let days = build(requests: nil, settings: weekdays)
        XCTAssertEqual(day(days, "2026-09-26").status, .notAsked)
        XCTAssertEqual(day(days, "2026-09-25").status, .missed)
    }

    /// Late is judged from the escalation timing (grace + one interval = the
    /// owner is alerted), not a hardcoded 8:00 + 2h.
    func testFallbackLateThresholdIsTheOwnerAlert() {
        let days = build(
            checkIns: [checkIn("2026-09-24T09:40:00Z"), checkIn("2026-09-25T09:50:00Z")],
            requests: nil,
            settings: settings(checkinTime: "09:00")   // grace 30 + interval 15 → 9:45
        )
        XCTAssertEqual(day(days, "2026-09-24").status, .onTime)
        XCTAssertEqual(day(days, "2026-09-25").status, .late)
    }

    /// Without a schedule, an evening check-in is not "late".
    func testFallbackWithoutScheduleNeverCallsACheckInLate() {
        let days = build(checkIns: [checkIn("2026-09-24T19:00:00Z")], requests: nil, settings: nil)
        XCTAssertEqual(day(days, "2026-09-24").status, .onTime)
    }

    func testDaysBeforeEnrollmentAreNotMissed() {
        let days = build(requests: nil, settings: settings(), enrolledSince: date("2026-09-25T12:00:00Z"))
        XCTAssertEqual(day(days, "2026-09-24").status, .notAsked)
        XCTAssertEqual(day(days, "2026-09-25").status, .missed)
    }

    // MARK: - Summary

    func testStatsCountOnlyResolvedDays() {
        let days = build(
            checkIns: [checkIn("2026-09-22T09:05:00Z"), checkIn("2026-09-23T09:05:00Z")],
            requests: [
                request("2026-09-22T09:00:00Z", status: .checkedIn),
                request("2026-09-23T09:00:00Z", status: .checkedIn),
                request("2026-09-24T09:00:00Z", status: .missed, step: 3),
                request("2026-09-27T09:00:00Z", status: .pending, step: 1, next: date("2026-09-27T16:00:00Z")),
            ],
            settings: settings()
        )
        let stats = HistoryTimeline.stats(for: days)
        XCTAssertEqual(stats.expectedDays, 3)
        XCTAssertEqual(stats.answeredDays, 2)
        XCTAssertEqual(stats.missedDays, 1)
        XCTAssertEqual(stats.percent, 67)
    }

    func testNothingExpectedHasNoPercent() {
        XCTAssertNil(HistoryTimeline.stats(for: build()).percent)
    }

    /// Same rule as the dashboard: a not-yet-done today doesn't zero it.
    func testStreakCountsFromYesterdayBeforeTodaysCheckIn() {
        let checkIns = [checkIn("2026-09-25T09:00:00Z"), checkIn("2026-09-26T09:00:00Z")]
        XCTAssertEqual(HistoryTimeline.currentStreak(checkIns: checkIns, now: now, calendar: utc), 2)
    }

    /// The dashboard reads 30 days of check-ins for its streak; a 90-day
    /// History load must not print a longer one for the same person.
    func testStreakUsesTheDashboardsThirtyDayLookback() {
        let checkIns = (0..<60).map { offset -> CheckIn in
            let at = utc.date(byAdding: .day, value: -offset, to: date("2026-09-27T09:00:00Z"))!
            return CheckIn(id: UUID(), receiverId: UUID(), familyId: UUID(), checkedInAt: at, source: .app)
        }
        XCTAssertEqual(HistoryTimeline.currentStreak(checkIns: checkIns, now: now, calendar: utc), 30)
    }

    // MARK: - Wording

    func testSourceLabelsAreWordsNotEnumValues() {
        XCTAssertEqual(HistoryTimeline.sourceLabel(.onDemand), "Answered your request")
        XCTAssertEqual(HistoryTimeline.sourceLabel(.needHelp), "From the notification")
        let event = HistoryEvent(
            id: "x", at: now,
            kind: .checkIn(checkIn("2026-09-27T09:00:00Z", mood: .havingFun, source: .onDemand), help: nil, afterAlert: false)
        )
        XCTAssertEqual(HistoryTimeline.detail(for: event), "Mood: Having Fun · Answered your request")
    }

    // MARK: - Schedule RPC shape (00057)

    /// family_receiver_schedules returns the table's column names minus the
    /// home coordinates and the receiver's own display preferences, with
    /// Postgres TIME values ("08:00:00"). The app's model must decode it.
    func testScheduleRPCRowDecodes() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","family_member_id":"\(UUID().uuidString)",
          "checkin_time":"08:00:00","timezone":"America/Chicago",
          "grace_period_minutes":30,"reminder_interval_minutes":30,"escalation_enabled":true,
          "quiet_hours_start":null,"quiet_hours_end":null,"mood_tracking_enabled":true,
          "sms_escalation_enabled":false,"is_active":true,"location_tracking_enabled":false,
          "geofence_radius_meters":500,"location_alert_enabled":false,"receiver_mode":"standard",
          "schedule_type":"weekday_weekend","weekend_checkin_time":"10:00:00",
          "custom_schedule":null,"schedule_paused":false,"paused_until":null}]
        """
        let rows = try JSONDecoder().decode([ReceiverSettings].self, from: Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].homeLatitude)
        XCTAssertEqual(rows[0].scheduleType, .weekdayWeekend)
        XCTAssertEqual(ReceiverViewModel.parseCheckinTime(rows[0].checkinTime)?.hour, 8)
    }

    // MARK: - Calendar layout

    func testHeatmapColumnsPadToWholeWeeks() {
        let days = build(days: 7) // Mon Sep 21 … Sun Sep 27
        let columns = CalendarHeatmapView.columns(for: days, calendar: utc)
        XCTAssertEqual(columns.count, 2)
        XCTAssertTrue(columns.allSatisfy { $0.count == 7 })
        XCTAssertNil(columns[0][0], "Sunday before the window is padding")
        XCTAssertEqual(columns[0][1]?.date, date("2026-09-21T00:00:00Z"))
        XCTAssertEqual(columns[1][0]?.date, date("2026-09-27T00:00:00Z"))
        XCTAssertNil(columns[1][1])
    }

    func testMonthLabelSitsOverTheColumnWhereTheMonthStarts() {
        let days = build(days: 30) // Aug 29 … Sep 27
        let columns = CalendarHeatmapView.columns(for: days, calendar: utc)
        let labels = CalendarHeatmapView.monthLabels(for: columns, calendar: utc)
        let septemberColumn = columns.firstIndex { $0.contains { $0?.date == self.date("2026-09-01T00:00:00Z") } }!
        XCTAssertNotNil(labels[septemberColumn])
        // August starts one column before September: its label would collide.
        XCTAssertNil(labels[0])
    }

    // MARK: - Trend

    func testTrendUsesOnlyTheFirstCheckInOfEachDay() {
        let firsts = CheckInTrendChartView.firstCheckInMinutes(
            checkIns: [checkIn("2026-09-26T08:00:00Z"), checkIn("2026-09-26T20:00:00Z"), checkIn("2026-09-25T07:30:00Z")],
            days: 7, calendar: utc, now: now
        )
        XCTAssertEqual(firsts.map { $0.minutes }, [450, 480])
    }

    func testTrendTimesFollowTheReadersClock() {
        let text = CheckInTrendChartView.formatMinutes(21 * 60 + 14, calendar: utc, locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(text, "21:14")
    }
}
