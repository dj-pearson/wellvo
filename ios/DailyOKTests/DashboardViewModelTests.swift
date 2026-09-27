import XCTest
@testable import DailyOK

/// Tests for DashboardViewModel business logic: streak calculation, weekly summary
final class DashboardViewModelTests: XCTestCase {

    // MARK: - Streak Calculation

    func testStreakWithConsecutiveDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let checkIns = (0..<5).map { dayOffset -> CheckIn in
            makeCheckIn(daysAgo: dayOffset)
        }

        let streak = calculateStreak(from: checkIns)
        XCTAssertEqual(streak, 5, "Should count 5 consecutive days including today")
    }

    func testStreakWithGap() {
        // Today and yesterday checked in, but not 2 days ago
        let checkIns = [makeCheckIn(daysAgo: 0), makeCheckIn(daysAgo: 1)]
        let streak = calculateStreak(from: checkIns)
        XCTAssertEqual(streak, 2, "Should count 2 days before the gap")
    }

    func testStreakWithNoCheckIns() {
        let streak = calculateStreak(from: [])
        XCTAssertEqual(streak, 0, "Empty history should give 0 streak")
    }

    /// Today not done YET must not zero the streak every morning — the owner
    /// used to see a 30-day streak drop to "0 day streak" before breakfast.
    func testStreakWhenTodayNotYetDone() {
        // Only yesterday checked in (not today)
        let checkIns = [makeCheckIn(daysAgo: 1)]
        let streak = calculateStreak(from: checkIns)
        XCTAssertEqual(streak, 1, "A not-yet-done today keeps yesterday's streak")
    }

    func testStreakBrokenByAMissedDay() {
        let checkIns = [makeCheckIn(daysAgo: 2), makeCheckIn(daysAgo: 3)]
        XCTAssertEqual(calculateStreak(from: checkIns), 0)
    }

    // MARK: - Weekly Summary Computation

    func testWeeklySummaryConsistency() {
        let checkIns = (0..<5).map { makeCheckIn(daysAgo: $0) }
        let summary = computeWeeklySummary(checkIns: checkIns, receiverCount: 1)

        // 5 check-ins out of 7 expected = ~71.4%
        XCTAssertEqual(summary.totalCheckIns, 5)
        XCTAssertEqual(summary.totalExpected, 7)
        XCTAssertGreaterThan(summary.consistencyPercentage, 70)
        XCTAssertLessThan(summary.consistencyPercentage, 72)
    }

    func testWeeklySummaryWithMultipleReceivers() {
        let checkIns = (0..<10).map { makeCheckIn(daysAgo: $0 % 7) }
        let summary = computeWeeklySummary(checkIns: checkIns, receiverCount: 2)

        // 2 receivers × 7 days = 14 expected
        XCTAssertEqual(summary.totalExpected, 14)
    }

    func testWeeklySummaryMoodBreakdown() {
        let checkIns = [
            makeCheckIn(daysAgo: 0, mood: .happy),
            makeCheckIn(daysAgo: 1, mood: .happy),
            makeCheckIn(daysAgo: 2, mood: .tired),
            makeCheckIn(daysAgo: 3, mood: nil),
        ]
        let summary = computeWeeklySummary(checkIns: checkIns, receiverCount: 1)

        XCTAssertEqual(summary.moodBreakdown[.happy], 2)
        XCTAssertEqual(summary.moodBreakdown[.tired], 1)
        XCTAssertNil(summary.moodBreakdown[.neutral])
    }

    func testWeeklySummaryNoReceivers() {
        let summary = computeWeeklySummary(checkIns: [], receiverCount: 0)
        XCTAssertEqual(summary.consistencyPercentage, 0)
        XCTAssertEqual(summary.averageCheckInTime, "--")
    }

    // MARK: - Receiver Status

    func testReceiverCheckInStatusLabels() {
        XCTAssertEqual(ReceiverCheckInStatus.checkedIn.label, "Checked In")
        XCTAssertEqual(ReceiverCheckInStatus.pending.label, "Pending")
        XCTAssertEqual(ReceiverCheckInStatus.missed.label, "Missed")
        XCTAssertEqual(ReceiverCheckInStatus.noData.label, "No Data")
    }

    func testReceiverCheckInStatusIcons() {
        XCTAssertEqual(ReceiverCheckInStatus.checkedIn.icon, "checkmark.circle.fill")
        XCTAssertEqual(ReceiverCheckInStatus.missed.icon, "exclamationmark.circle.fill")
    }

    // MARK: - On-demand status resolution (US-IOS020)

    func testResolveStatusCheckedInWhenNoActiveRequest() {
        let result = DashboardViewModel.resolveStatus(
            todayCheckIn: makeCheckIn(at: Date()),
            activeRequest: nil
        )
        XCTAssertEqual(result.status.label, ReceiverCheckInStatus.checkedIn.label)
        XCTAssertEqual(result.escalationStep, 0)
    }

    func testResolveStatusPendingWhenNothing() {
        let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: nil)
        XCTAssertEqual(result.status.label, ReceiverCheckInStatus.pending.label)
    }

    /// The core US-IOS020 bug: a receiver who already checked in this morning,
    /// then receives an on-demand request that is still pending, must show as
    /// awaiting response — NOT as "checked in".
    func testResolveStatusOnDemandRequestAfterCheckInIsPending() {
        let now = Date()
        let morningCheckIn = makeCheckIn(at: now.addingTimeInterval(-6 * 3600))
        let onDemand = makeRequest(createdAt: now, status: .pending, type: .onDemand, escalationStep: 2)

        let result = DashboardViewModel.resolveStatus(
            todayCheckIn: morningCheckIn,
            activeRequest: onDemand
        )
        XCTAssertEqual(
            result.status.label,
            ReceiverCheckInStatus.pending.label,
            "An on-demand request sent after the morning check-in must not be masked by 'checked in today'"
        )
        XCTAssertEqual(result.escalationStep, 2)
    }

    /// A request that predates the most recent check-in has been answered (the
    /// check-in postdates it), so the receiver is checked in with no escalation.
    func testResolveStatusRequestBeforeCheckInIsCheckedIn() {
        let now = Date()
        let staleRequest = makeRequest(createdAt: now.addingTimeInterval(-3600), status: .pending, escalationStep: 1)
        let checkIn = makeCheckIn(at: now)

        let result = DashboardViewModel.resolveStatus(
            todayCheckIn: checkIn,
            activeRequest: staleRequest
        )
        XCTAssertEqual(result.status.label, ReceiverCheckInStatus.checkedIn.label)
        XCTAssertEqual(result.escalationStep, 0)
    }

    func testResolveStatusMissedRequestWithNoCheckIn() {
        let missed = makeRequest(createdAt: Date(), status: .missed, escalationStep: 3)
        let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: missed)
        XCTAssertEqual(result.status.label, ReceiverCheckInStatus.missed.label)
        XCTAssertEqual(result.escalationStep, 3)
    }

    /// US-IOS023: the Live Activity "overdue since" anchor must be the request's
    /// created_at, so it survives an app restart rather than resetting to now.
    func testResolveStatusDueSinceIsRequestCreatedAt() {
        let createdAt = Date().addingTimeInterval(-40 * 60) // 40 minutes ago
        let request = makeRequest(createdAt: createdAt, status: .pending, escalationStep: 2)
        let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: request)
        XCTAssertEqual(result.dueSince, createdAt)
    }

    func testResolveStatusDueSinceNilWhenCheckedIn() {
        let result = DashboardViewModel.resolveStatus(
            todayCheckIn: makeCheckIn(at: Date()),
            activeRequest: nil
        )
        XCTAssertNil(result.dueSince)
    }

    // MARK: - Missed requests don't resurface after a later check-in

    /// Missed rows are never closed server-side. A miss last week that was
    /// followed by check-ins must not show as "Missed" again this morning.
    func testOldMissedRequestAnsweredByLaterCheckInIsNotMissed() {
        let now = Date()
        let missedLastWeek = makeRequest(createdAt: now.addingTimeInterval(-6 * 86_400), status: .missed, escalationStep: 3)
        let result = DashboardViewModel.resolveStatus(
            todayCheckIn: nil,
            activeRequest: missedLastWeek,
            latestCheckInAt: now.addingTimeInterval(-1 * 86_400)
        )
        XCTAssertNotEqual(result.status, .missed)
        XCTAssertEqual(result.escalationStep, 0)
        XCTAssertNil(result.dueSince)
    }

    func testMissedRequestWithNoCheckInSinceStaysMissed() {
        let now = Date()
        let missed = makeRequest(createdAt: now.addingTimeInterval(-2 * 86_400), status: .missed, escalationStep: 3)
        let result = DashboardViewModel.resolveStatus(
            todayCheckIn: nil,
            activeRequest: missed,
            latestCheckInAt: now.addingTimeInterval(-3 * 86_400)
        )
        XCTAssertEqual(result.status, .missed)
    }

    // MARK: - Stand-down

    func testStoodDownRequestStopsEscalation() {
        let now = Date()
        let request = makeRequest(createdAt: now.addingTimeInterval(-3600), status: .pending,
                                  escalationStep: 2, nextEscalationAt: nil, stoodDownAt: now)
        let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: request)
        XCTAssertTrue(result.stoodDown)
        XCTAssertEqual(result.escalationStep, 0, "The banner and Live Activity must not come back after a stand-down")
        XCTAssertNil(result.dueSince)
        XCTAssertEqual(result.stoodDownAt, now)
    }

    /// Older backend without stood_down_at: a stepped, pending request with no
    /// next step was stood down (escalation_tick always schedules one).
    func testClearedEscalationClockIsInferredAsStoodDown() {
        let request = makeRequest(createdAt: Date().addingTimeInterval(-3600), status: .pending,
                                  escalationStep: 1, nextEscalationAt: nil)
        let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: request)
        XCTAssertTrue(result.stoodDown)
        XCTAssertEqual(result.escalationStep, 0)
    }

    func testStoodDownMissedRequestKeepsMissedButStopsEscalation() {
        let request = makeRequest(createdAt: Date().addingTimeInterval(-3600), status: .missed,
                                  escalationStep: 3, stoodDownAt: Date())
        let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: request)
        XCTAssertEqual(result.status, .missed)
        XCTAssertTrue(result.stoodDown)
        XCTAssertEqual(result.escalationStep, 0)
    }

    /// A snooze or an undone check-in re-arms next_escalation_at on a request
    /// that was stood down earlier; the dashboard must show the escalation
    /// again, not "Alerts stopped".
    func testReArmedEscalationIsNotStoodDown() {
        let now = Date()
        let request = makeRequest(createdAt: now.addingTimeInterval(-3600), status: .pending,
                                  escalationStep: 1, nextEscalationAt: now.addingTimeInterval(600),
                                  stoodDownAt: now.addingTimeInterval(-1800))
        let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: request)
        XCTAssertFalse(result.stoodDown)
        XCTAssertEqual(result.escalationStep, 1)
    }

    func testUnsteppedPendingRequestIsNotStoodDown() {
        let request = makeRequest(createdAt: Date(), status: .pending, escalationStep: 0, nextEscalationAt: nil)
        let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: request)
        XCTAssertFalse(result.stoodDown)
    }

    // MARK: - Help requests outrank "checked in"

    func testNeedHelpCheckInIsNeedsHelpNotCheckedIn() {
        let checkIn = CheckIn(id: UUID(), receiverId: UUID(), familyId: UUID(),
                              checkedInAt: Date(), source: .notification, responseType: .needHelp)
        let result = DashboardViewModel.resolveStatus(todayCheckIn: checkIn, activeRequest: nil)
        XCTAssertEqual(result.status, .needsHelp)
        XCTAssertEqual(result.helpKind, .needHelp)
    }

    func testCallMeCheckInIsNeedsHelp() {
        let checkIn = CheckIn(id: UUID(), receiverId: UUID(), familyId: UUID(),
                              checkedInAt: Date(), source: .notification, responseType: .callMe)
        XCTAssertEqual(DashboardViewModel.resolveStatus(todayCheckIn: checkIn, activeRequest: nil).helpKind, .callMe)
    }

    func testKidSOSIsNeedsHelp() {
        let checkIn = CheckIn(id: UUID(), receiverId: UUID(), familyId: UUID(),
                              checkedInAt: Date(), source: .app, responseType: .ok, kidResponseType: "sos")
        let result = DashboardViewModel.resolveStatus(todayCheckIn: checkIn, activeRequest: nil)
        XCTAssertEqual(result.status, .needsHelp)
        XCTAssertEqual(result.helpKind, .sos)
    }

    func testOkCheckInIsNotAHelpRequest() {
        let checkIn = CheckIn(id: UUID(), receiverId: UUID(), familyId: UUID(),
                              checkedInAt: Date(), source: .app, responseType: .ok)
        XCTAssertEqual(DashboardViewModel.resolveStatus(todayCheckIn: checkIn, activeRequest: nil).status, .checkedIn)
    }

    // MARK: - Not due yet vs pending

    func testNothingDueYetIsUpcomingNotPending() {
        let later = Date().addingTimeInterval(3 * 3600)
        for schedule in [ReceiverScheduleState.notYetDue(later), .offToday, .paused] {
            let result = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: nil, schedule: schedule)
            XCTAssertEqual(result.status, .upcoming, "\(schedule)")
        }
    }

    func testPassedDueTimeWithNoCheckInIsPending() {
        let result = DashboardViewModel.resolveStatus(
            todayCheckIn: nil, activeRequest: nil, schedule: .due(Date().addingTimeInterval(-3600))
        )
        XCTAssertEqual(result.status, .pending)
    }

    /// An outstanding request always wins over "not due yet".
    func testOutstandingRequestBeatsNotYetDue() {
        let request = makeRequest(createdAt: Date(), status: .pending)
        let result = DashboardViewModel.resolveStatus(
            todayCheckIn: nil, activeRequest: request, schedule: .notYetDue(Date().addingTimeInterval(3600))
        )
        XCTAssertEqual(result.status, .pending)
    }

    // 2026-06-10 is a Wednesday, 2026-06-13 a Saturday (UTC).

    func testScheduleStateBeforeFirstTimeIsNotYetDue() {
        let s = makeSettings(checkinTime: "09:00")
        XCTAssertEqual(
            DashboardViewModel.scheduleState(settings: s, now: iso("2026-06-10T06:00:00Z"), calendar: utc),
            .notYetDue(iso("2026-06-10T09:00:00Z"))
        )
    }

    func testScheduleStateAfterTimeIsDue() {
        let s = makeSettings(checkinTime: "09:00")
        XCTAssertEqual(
            DashboardViewModel.scheduleState(settings: s, now: iso("2026-06-10T10:00:00Z"), calendar: utc),
            .due(iso("2026-06-10T09:00:00Z"))
        )
    }

    func testScheduleStatePausedAndOffDay() {
        XCTAssertEqual(
            DashboardViewModel.scheduleState(settings: makeSettings(schedulePaused: true),
                                             now: iso("2026-06-10T10:00:00Z"), calendar: utc),
            .paused
        )
        let weekdaysOnly = makeSettings(
            scheduleType: "custom",
            customSchedule: ["mon": "08:00", "tue": "08:00", "wed": "08:00", "thu": "08:00", "fri": "08:00"]
        )
        XCTAssertEqual(
            DashboardViewModel.scheduleState(settings: weekdaysOnly, now: iso("2026-06-13T10:00:00Z"), calendar: utc),
            .offToday
        )
    }

    func testScheduleStateUnknownWithoutSettings() {
        XCTAssertEqual(DashboardViewModel.scheduleState(settings: nil, now: Date(), calendar: utc), .unknown)
    }

    // MARK: - Status detail

    func testStatusDetailForSnoozedRequest() {
        let now = Date()
        let request = makeRequest(createdAt: now.addingTimeInterval(-600), status: .pending,
                                  snoozedUntil: now.addingTimeInterval(900))
        let resolved = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: request)
        let detail = DashboardViewModel.statusDetail(resolved: resolved, todayCheckIn: nil,
                                                     schedule: .unknown, timezone: nil, now: now)
        XCTAssertTrue(detail?.hasPrefix("Snoozed until") ?? false, detail ?? "nil")
    }

    func testStatusDetailForOffDay() {
        let resolved = DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: nil, schedule: .offToday)
        XCTAssertEqual(
            DashboardViewModel.statusDetail(resolved: resolved, todayCheckIn: nil, schedule: .offToday, timezone: nil),
            "No check-in scheduled today"
        )
    }

    // MARK: - Receiver-zone times

    func testReceiverTimeIsLabelledWhenZonesDiffer() {
        let date = iso("2026-06-10T15:05:00Z")
        let text = ReceiverTime.format(date, timezone: "America/Los_Angeles",
                                       device: TimeZone(identifier: "America/New_York")!)
        XCTAssertTrue(text.contains("8:05") || text.contains("08:05"), text)
        XCTAssertTrue(text.contains("PDT") || text.contains("GMT-7"), text)
    }

    func testReceiverTimeIsUnlabelledInTheSameZone() {
        let date = iso("2026-06-10T15:05:00Z")
        let ny = TimeZone(identifier: "America/New_York")!
        let text = ReceiverTime.format(date, timezone: "America/New_York", device: ny)
        XCTAssertFalse(text.contains("EDT"), text)
    }

    // MARK: - Phone health

    func testDeviceHealthWarnsWhenPhoneSilentDuringOutstandingAnswer() {
        let now = Date()
        let health = DashboardViewModel.deviceHealth(lastSeenAt: now.addingTimeInterval(-4 * 3600),
                                                     batteryLevel: 0.6, answerOutstanding: true, now: now)
        XCTAssertEqual(health?.isWarning, true)
        let calm = DashboardViewModel.deviceHealth(lastSeenAt: now.addingTimeInterval(-4 * 3600),
                                                   batteryLevel: 0.6, answerOutstanding: false, now: now)
        XCTAssertEqual(calm?.isWarning, false)
    }

    func testDeviceHealthWarnsOnFlatBatteryAndDayOld() {
        let now = Date()
        XCTAssertEqual(DashboardViewModel.deviceHealth(lastSeenAt: now, batteryLevel: 0.05,
                                                       answerOutstanding: false, now: now)?.isWarning, true)
        XCTAssertEqual(DashboardViewModel.deviceHealth(lastSeenAt: now.addingTimeInterval(-25 * 3600), batteryLevel: nil,
                                                       answerOutstanding: false, now: now)?.isWarning, true)
        XCTAssertNil(DashboardViewModel.deviceHealth(lastSeenAt: nil, batteryLevel: 0.5, answerOutstanding: true, now: now))
    }

    // MARK: - Weekly summary

    func testLaggingReceiversNamesWhoIsSlippingWorstFirst() {
        let lines = DashboardViewModel.laggingReceivers([
            (name: "Mom", checkedIn: 7, scheduled: 7),
            (name: "Dad", checkedIn: 3, scheduled: 7),
            (name: "Sam", checkedIn: 1, scheduled: 5),
            (name: "New", checkedIn: 0, scheduled: 0),
        ])
        XCTAssertEqual(lines, ["Sam: 1 of 5 days", "Dad: 3 of 7 days"])
    }

    func testEmptyWeekHasNoData() {
        let summary = WeeklySummary(consistencyPercentage: 0, averageCheckInTime: "--",
                                    totalCheckIns: 0, totalExpected: 0, moodBreakdown: [:])
        XCTAssertFalse(summary.hasData)
    }

    // MARK: - Alerts

    func testUrgentUnacknowledgedAlertsSortFirst() throws {
        let old = try makeAlert(type: "need_help", createdAt: "2026-06-10T08:00:00Z")
        let newer = try makeAlert(type: "time_drift", createdAt: "2026-06-10T09:00:00Z")
        let handled = try makeAlert(type: "call_me", createdAt: "2026-06-10T09:30:00Z", acknowledged: true)
        let sorted = DashboardViewModel.sortAlerts([newer, handled, old])
        XCTAssertEqual(sorted.map(\.type), ["need_help", "call_me", "time_drift"])
    }

    func testUrgentAlertTypes() throws {
        XCTAssertTrue(DashboardViewModel.isUrgent(try makeAlert(type: "need_help", createdAt: "2026-06-10T08:00:00Z")))
        XCTAssertTrue(DashboardViewModel.isUrgent(try makeAlert(type: "call_me", createdAt: "2026-06-10T08:00:00Z")))
        XCTAssertFalse(DashboardViewModel.isUrgent(try makeAlert(type: "low_battery", createdAt: "2026-06-10T08:00:00Z")))
    }

    // MARK: - Card ordering

    func testNeedsHelpOutranksMissedOutranksCheckedIn() {
        func card(_ name: String, _ status: ReceiverCheckInStatus, step: Int = 0) -> ReceiverStatusCard {
            ReceiverStatusCard(id: UUID(), memberId: UUID(), name: name, avatarUrl: nil, phone: nil,
                               status: status, lastCheckIn: nil, streak: 0, mood: nil,
                               hasNotificationsEnabled: true, checkedInTime: nil, locationLabel: nil,
                               kidResponseType: nil, escalationStep: step)
        }
        let ranks = [card("A", .checkedIn), card("B", .missed), card("C", .needsHelp), card("D", .pending, step: 1), card("E", .upcoming)]
            .sorted { $0.urgencyRank < $1.urgencyRank }
            .map(\.name)
        XCTAssertEqual(ranks, ["C", "B", "D", "E", "A"])
    }

    // MARK: - Helpers

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func iso(_ value: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: value)!
    }

    private func makeAlert(type: String, createdAt: String, acknowledged: Bool = false) throws -> DailyOKAlert {
        var dict: [String: Any] = [
            "id": UUID().uuidString,
            "family_id": UUID().uuidString,
            "receiver_id": UUID().uuidString,
            "type": type,
            "title": "t",
            "message": "m",
            "is_read": false,
            "created_at": createdAt,
        ]
        if acknowledged {
            dict["acknowledged_at"] = createdAt
            dict["acknowledged_by"] = UUID().uuidString
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DailyOKAlert.self, from: JSONSerialization.data(withJSONObject: dict))
    }

    /// ReceiverSettings only has a Decodable init.
    private func makeSettings(
        scheduleType: String = "daily",
        checkinTime: String = "09:00",
        customSchedule: [String: String]? = nil,
        schedulePaused: Bool = false
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
            "receiver_mode": "standard",
            "schedule_type": scheduleType,
            "schedule_paused": schedulePaused,
            "notify_owner_on_checkin": true,
            "simple_mode": false,
            "audio_confirmation_enabled": false,
        ]
        if let customSchedule { dict["custom_schedule"] = customSchedule }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(ReceiverSettings.self, from: data)
    }

    // MARK: - Legacy helpers

    private func makeCheckIn(at date: Date) -> CheckIn {
        CheckIn(
            id: UUID(),
            receiverId: UUID(),
            familyId: UUID(),
            checkedInAt: date,
            mood: nil,
            source: .app
        )
    }

    /// A live escalation always has a next step scheduled (escalation_tick sets
    /// it on every step); a cleared clock on a stepped request means it was
    /// stood down, so the default here is a scheduled next step.
    private func makeRequest(
        createdAt: Date,
        status: CheckInRequestStatus,
        type: CheckInRequestType = .onDemand,
        escalationStep: Int = 0,
        nextEscalationAt: Date? = Date().addingTimeInterval(30 * 60),
        stoodDownAt: Date? = nil,
        snoozedUntil: Date? = nil
    ) -> CheckInRequest {
        var request = CheckInRequest(
            id: UUID(),
            familyId: UUID(),
            receiverId: UUID(),
            requestedBy: UUID(),
            type: type,
            status: status,
            createdAt: createdAt,
            respondedAt: nil,
            escalationStep: escalationStep,
            nextEscalationAt: nextEscalationAt
        )
        request.stoodDownAt = stoodDownAt
        request.snoozedUntil = snoozedUntil
        return request
    }

    private func makeCheckIn(daysAgo: Int, mood: Mood? = nil) -> CheckIn {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        // Set time to 8:30 AM
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var adjustedComponents = components
        adjustedComponents.hour = 8
        adjustedComponents.minute = 30
        let adjustedDate = calendar.date(from: adjustedComponents)!

        return CheckIn(
            id: UUID(),
            receiverId: UUID(),
            familyId: UUID(),
            checkedInAt: adjustedDate,
            mood: mood,
            source: .app,
            scheduledFor: nil
        )
    }

    /// The dashboard now uses the shared Streaks rule (the receiver's home
    /// screen uses the same one), so these exercise it directly.
    private func calculateStreak(from checkIns: [CheckIn]) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Streaks.currentStreak(isoTimestamps: checkIns.map { formatter.string(from: $0.checkedInAt) })
    }

    /// Mirror of DashboardViewModel.computeWeeklySummary for testing
    private func computeWeeklySummary(checkIns: [CheckIn], receiverCount: Int) -> WeeklySummary {
        let totalExpected = receiverCount * 7
        let totalCheckIns = checkIns.count
        let consistency = totalExpected > 0 ? (Double(totalCheckIns) / Double(totalExpected)) * 100 : 0

        let avgTime: String
        if !checkIns.isEmpty {
            let calendar = Calendar.current
            let totalMinutes = checkIns.reduce(0) { sum, checkIn in
                let components = calendar.dateComponents([.hour, .minute], from: checkIn.checkedInAt)
                return sum + (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
            let avgMinutes = totalMinutes / checkIns.count
            let hour = avgMinutes / 60
            let minute = avgMinutes % 60
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            if let date = calendar.date(from: components) {
                avgTime = formatter.string(from: date)
            } else {
                avgTime = "--"
            }
        } else {
            avgTime = "--"
        }

        var moodBreakdown: [Mood: Int] = [:]
        for checkIn in checkIns {
            if let mood = checkIn.mood {
                moodBreakdown[mood, default: 0] += 1
            }
        }

        return WeeklySummary(
            consistencyPercentage: consistency,
            averageCheckInTime: avgTime,
            totalCheckIns: totalCheckIns,
            totalExpected: totalExpected,
            moodBreakdown: moodBreakdown
        )
    }
}

// MARK: - Co-caregiver (viewer) deep dive

/// What a co-caregiver's dashboard says and decides: their schedule comes from
/// family_receiver_schedules, escalation wording is true for them, claims
/// confirm, and informational alerts can't be "claimed".
final class ViewerDashboardTests: XCTestCase {
    private let fmt: (Date) -> String = { date in
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
    private let tenAM = Date(timeIntervalSince1970: 1_790_071_200) // 2026-09-22 10:00 UTC

    private func settings(member: UUID, paused: Bool = false, escalation: Bool = true) throws -> ReceiverSettings {
        let json = """
        {"id":"\(UUID().uuidString)","family_member_id":"\(member.uuidString)",
         "checkin_time":"08:00:00","timezone":"UTC",
         "grace_period_minutes":30,"reminder_interval_minutes":30,"escalation_enabled":\(escalation),
         "mood_tracking_enabled":true,"sms_escalation_enabled":false,"is_active":true,
         "location_tracking_enabled":false,"geofence_radius_meters":500,"location_alert_enabled":false,
         "schedule_paused":\(paused)}
        """
        return try JSONDecoder().decode(ReceiverSettings.self, from: Data(json.utf8))
    }

    // MARK: Schedules (deferred item: the dashboard read receiver_settings directly)

    func testViewerDirectReadIsEmptySoTheRPCFillsEveryone() throws {
        let mom = UUID(), dad = UUID()
        let rpc = [try settings(member: mom, paused: true), try settings(member: dad)]
        XCTAssertTrue(DashboardViewModel.needsScheduleFallback(direct: [], memberIds: [mom, dad]))
        let merged = DashboardViewModel.mergeSchedules(direct: [], fallback: rpc, memberIds: [mom, dad])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[mom]?.schedulePaused, true)
    }

    func testOwnerDirectRowsWinAndNoFallbackIsNeeded() throws {
        let mom = UUID()
        let direct = [try settings(member: mom, escalation: false)]
        XCTAssertFalse(DashboardViewModel.needsScheduleFallback(direct: direct, memberIds: [mom]))
        let merged = DashboardViewModel.mergeSchedules(direct: direct, fallback: [try settings(member: mom)], memberIds: [mom])
        XCTAssertEqual(merged[mom]?.escalationEnabled, false)
    }

    func testRPCRowsForPeopleNotOnTheDashboardAreIgnored() throws {
        let mom = UUID(), leftFamily = UUID()
        let merged = DashboardViewModel.mergeSchedules(
            direct: [], fallback: [try settings(member: mom), try settings(member: leftFamily)], memberIds: [mom]
        )
        XCTAssertEqual(Array(merged.keys), [mom])
    }

    func testMissingEverywhereStaysUnknown() {
        let mom = UUID()
        XCTAssertTrue(DashboardViewModel.mergeSchedules(direct: [], fallback: nil, memberIds: [mom]).isEmpty)
    }

    func testAPausedScheduleFromTheRPCReadsNotDueForAViewer() throws {
        // Before: no settings → .unknown → "Pending" all day.
        let paused = try settings(member: UUID(), paused: true)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let schedule = DashboardViewModel.scheduleState(settings: paused, now: tenAM, calendar: utc)
        XCTAssertEqual(schedule, .paused)
        XCTAssertEqual(DashboardViewModel.resolveStatus(todayCheckIn: nil, activeRequest: nil, schedule: schedule).status, .upcoming)
    }

    // MARK: Escalation wording

    func testOwnerWordingIsUnchanged() {
        let text = DashboardViewModel.escalationText(
            name: "Mom", status: .pending, step: 2, nextEscalationAt: tenAM,
            reminderIntervalMinutes: 30, isViewer: false, ownerName: "Sarah", formatTime: fmt
        )
        XCTAssertEqual(text, "You've been alerted. Other caregivers will be alerted at 10:00 if there's still no answer.")
    }

    func testViewerStepOneSaysTheOwnerThenThem() {
        let text = DashboardViewModel.escalationText(
            name: "Mom", status: .pending, step: 1, nextEscalationAt: tenAM,
            reminderIntervalMinutes: 30, isViewer: true, ownerName: "Sarah", formatTime: fmt
        )
        XCTAssertEqual(text, "Reminder re-sent to Mom. Sarah will be alerted at 10:00 and you at 10:30 if there's still no answer.")
    }

    func testViewerStepTwoSaysTheOwnerWasAlertedNotThem() {
        let text = DashboardViewModel.escalationText(
            name: "Mom", status: .pending, step: 2, nextEscalationAt: tenAM,
            reminderIntervalMinutes: 30, isViewer: true, ownerName: "Sarah", formatTime: fmt
        )
        XCTAssertEqual(text, "Sarah has been alerted. You'll be alerted at 10:00 if there's still no answer.")
        XCTAssertFalse(text.contains("You've been alerted"))
    }

    func testViewerStepThreeAndMissed() {
        XCTAssertEqual(
            DashboardViewModel.escalationText(name: "Mom", status: .pending, step: 3, nextEscalationAt: nil,
                                              reminderIntervalMinutes: nil, isViewer: true, ownerName: nil, formatTime: fmt),
            "You and the family owner have been alerted. Mom still hasn't answered."
        )
        XCTAssertTrue(
            DashboardViewModel.escalationText(name: "Mom", status: .missed, step: 3, nextEscalationAt: nil,
                                              reminderIntervalMinutes: nil, isViewer: true, ownerName: "Sarah", formatTime: fmt)
                .contains("including you")
        )
    }

    func testViewerStepOneWithoutAnIntervalStillOrdersThem() {
        let text = DashboardViewModel.escalationText(
            name: "Mom", status: .pending, step: 1, nextEscalationAt: tenAM,
            reminderIntervalMinutes: nil, isViewer: true, ownerName: "Sarah", formatTime: fmt
        )
        XCTAssertEqual(text, "Reminder re-sent to Mom. Sarah will be alerted at 10:00, then you, if there's still no answer.")
    }

    func testEscalationOffTellsAViewerWhoToAsk() {
        XCTAssertTrue(DashboardViewModel.escalationOffText(name: "Dad", isViewer: false, ownerName: "Sarah").hasPrefix("Escalation is off"))
        let viewer = DashboardViewModel.escalationOffText(name: "Dad", isViewer: true, ownerName: "Sarah")
        XCTAssertTrue(viewer.contains("nobody, including you"))
        XCTAssertTrue(viewer.hasSuffix("Ask Sarah to turn them on."))
    }

    // MARK: Claims

    func testHandlingLineSaysYouToTheClaimer() {
        XCTAssertEqual(DashboardViewModel.handlingLine(name: "Sarah", isMine: true), "You're handling this")
        XCTAssertEqual(DashboardViewModel.handlingLine(name: "Tom", isMine: false), "Tom is handling this")
        XCTAssertEqual(DashboardViewModel.handlingLine(name: nil, isMine: false), "A caregiver is handling this")
    }

    func testMissedCheckInClaimLine() {
        XCTAssertTrue(DashboardViewModel.claimLine(name: "Tom", at: nil, isMine: false) == "Tom is on it")
        XCTAssertTrue(DashboardViewModel.claimLine(name: "Tom", at: nil, isMine: true) == "You're on it")
        XCTAssertTrue(DashboardViewModel.claimLine(name: nil, at: tenAM, isMine: false).hasPrefix("A caregiver is on it ("))
    }

    func testClaimColumnsDecodeAndAreOptional() throws {
        let base = """
        "id":"\(UUID().uuidString)","family_id":"\(UUID().uuidString)","receiver_id":"\(UUID().uuidString)",
        "requested_by":"\(UUID().uuidString)","type":"scheduled","status":"missed",
        "created_at":"2026-09-27T09:00:00Z","escalation_step":3
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(CheckInRequest.self, from: Data("{\(base)}".utf8))
        XCTAssertNil(old.claimedBy)
        let claimer = UUID()
        let claimed = try decoder.decode(CheckInRequest.self, from: Data(
            "{\(base),\"claimed_by\":\"\(claimer.uuidString)\",\"claimed_by_name\":\"Tom\",\"claimed_at\":\"2026-09-27T09:42:00Z\"}".utf8
        ))
        XCTAssertEqual(claimed.claimedBy, claimer)
        XCTAssertEqual(claimed.claimedByName, "Tom")
    }

    func testLeftTheFamilyIsNotClaimable() {
        XCTAssertFalse(DashboardViewModel.isClaimable(alert(type: "member_left")))
        XCTAssertTrue(DashboardViewModel.isClaimable(alert(type: "need_help")))
        XCTAssertTrue(DashboardViewModel.isClaimable(alert(type: "stale_heartbeat")))
    }

    func testClaimAndReleaseAreAnnounced() {
        XCTAssertEqual(DashboardViewModel.acknowledgementAnnouncement(release: false, receiverName: "Mom"),
                       "You're handling this for Mom. Other caregivers can see that.")
        XCTAssertNotNil(DashboardViewModel.acknowledgementAnnouncement(release: true, receiverName: nil))
    }

    private func alert(type: String) -> DailyOKAlert {
        let json = """
        {"id":"\(UUID().uuidString)","family_id":"\(UUID().uuidString)","receiver_id":"\(UUID().uuidString)",
         "type":"\(type)","title":"t","message":"m","is_read":false,"created_at":"2026-09-27T09:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(DailyOKAlert.self, from: Data(json.utf8))
    }
}

/// The co-caregiver's Settings: who is on the care team, and the words.
final class ViewerCareTeamTests: XCTestCase {
    private let familyId = UUID()
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func member(_ name: String, role: UserRole, id: UUID = UUID(), status: MemberStatus = .active, phone: String? = nil) -> FamilyMember {
        FamilyMember(
            id: UUID(), familyId: familyId, userId: id, role: role, status: status,
            invitedAt: nil, joinedAt: now,
            user: AppUser(id: id, email: nil, phone: phone, displayName: name, role: role,
                          createdAt: now, updatedAt: now)
        )
    }

    func testOwnerFirstThenCoCaregiversNotMeNotReceiversNotRemoved() {
        let ownerId = UUID(), me = UUID()
        let members = [
            member("Zoe", role: .viewer),
            member("Me", role: .viewer, id: me),
            member("Mom", role: .receiver),
            member("Sarah", role: .owner, id: ownerId, phone: "+15551234567"),
            member("Ann", role: .viewer),
            member("Gone", role: .viewer, status: .deactivated),
        ]
        let people = ViewerCareTeam.people(members: members, ownerId: ownerId, me: me)
        XCTAssertEqual(people.map(\.name), ["Sarah", "Ann", "Zoe"])
        XCTAssertTrue(people[0].isOwner)
        XCTAssertEqual(people[0].phone, "+15551234567")
    }

    func testLeaveCopyNamesWhoTheyStopHearingAbout() {
        let members = [member("Mom", role: .receiver), member("Sarah", role: .owner), member("Dad", role: .receiver)]
        let names = ViewerCareTeam.receiverNames(members: members)
        XCTAssertTrue(names?.contains("Mom") ?? false)
        XCTAssertTrue(names?.contains("Dad") ?? false)
        XCTAssertNil(ViewerCareTeam.receiverNames(members: [member("Sarah", role: .owner)]))
    }

    func testFooterMentionsHelpRequestsAndTheOwner() {
        let footer = ViewerCareTeam.roleFooter(ownerName: "Sarah")
        XCTAssertTrue(footer.contains("asks for help"))
        XCTAssertTrue(footer.contains("Sarah"))
    }
}
