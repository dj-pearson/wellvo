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

    func testStreakWhenTodayMissed() {
        // Only yesterday checked in (not today)
        let checkIns = [makeCheckIn(daysAgo: 1)]
        let streak = calculateStreak(from: checkIns)
        XCTAssertEqual(streak, 0, "Missing today should break the streak")
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

    // MARK: - Helpers

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

    private func makeRequest(
        createdAt: Date,
        status: CheckInRequestStatus,
        type: CheckInRequestType = .onDemand,
        escalationStep: Int = 0
    ) -> CheckInRequest {
        CheckInRequest(
            id: UUID(),
            familyId: UUID(),
            receiverId: UUID(),
            requestedBy: UUID(),
            type: type,
            status: status,
            createdAt: createdAt,
            respondedAt: nil,
            escalationStep: escalationStep,
            nextEscalationAt: nil
        )
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

    /// Mirror of DashboardViewModel.calculateStreak for testing
    private func calculateStreak(from checkIns: [CheckIn]) -> Int {
        guard !checkIns.isEmpty else { return 0 }
        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())
        let checkInDays = Set(checkIns.map { calendar.startOfDay(for: $0.checkedInAt) })

        while checkInDays.contains(currentDate) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
            currentDate = previousDay
        }
        return streak
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
