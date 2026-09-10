import XCTest
@testable import DailyOK

/// The watch's offline queue used to be a single slot valid only for "today".
/// Two check-ins the receiver genuinely made were lost by it:
///
///  - a tap at 23:55 that had not flushed by midnight was read as stale and
///    cleared, after the watch had already played the success haptic;
///  - a tap on a new day, while the previous day's was still pending, had
///    nowhere to go.
///
/// These cover the rules that replaced it (US-IOS147).
final class OfflineMarkerPolicyTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return cal
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func marker(_ value: String, _ type: String = "ok") -> OfflineCheckInMarker {
        OfflineCheckInMarker(at: date(value), type: type)
    }

    // MARK: - The 23:55 case

    func testATapJustBeforeMidnightSurvivesTheDayRollover() {
        let queued = [marker("2026-03-09 23:55")]
        let afterMidnight = date("2026-03-10 00:05")
        XCTAssertEqual(OfflineMarkerPolicy.prune(queued, now: afterMidnight), queued)
    }

    func testANewDaysTapDoesNotDisplaceTheOneStillWaiting() {
        var queue = [marker("2026-03-09 23:55")]
        queue = OfflineMarkerPolicy.enqueue(
            queue,
            adding: marker("2026-03-10 08:00"),
            calendar: calendar,
            now: date("2026-03-10 08:00")
        )
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.first?.at, date("2026-03-09 23:55"))
    }

    // MARK: - One marker per day

    func testARepeatTapOnTheSameDayDoesNotQueueASecond() {
        var queue = [marker("2026-03-10 08:00")]
        queue = OfflineMarkerPolicy.enqueue(
            queue,
            adding: marker("2026-03-10 08:02"),
            calendar: calendar,
            now: date("2026-03-10 08:02")
        )
        XCTAssertEqual(queue.count, 1)
        // The moment the receiver FIRST answered is the one that counts.
        XCTAssertEqual(queue.first?.at, date("2026-03-10 08:00"))
    }

    func testAnUrgentTapUpgradesTheDaysMarker() {
        var queue = [marker("2026-03-10 08:00", "ok")]
        queue = OfflineMarkerPolicy.enqueue(
            queue,
            adding: marker("2026-03-10 08:05", "need_help"),
            calendar: calendar,
            now: date("2026-03-10 08:05")
        )
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.first?.type, "need_help")
    }

    func testAPlainOKNeverDowngradesAnUrgentMarker() {
        var queue = [marker("2026-03-10 08:00", "need_help")]
        queue = OfflineMarkerPolicy.enqueue(
            queue,
            adding: marker("2026-03-10 09:00", "ok"),
            calendar: calendar,
            now: date("2026-03-10 09:00")
        )
        XCTAssertEqual(queue.first?.type, "need_help")
    }

    // MARK: - The replay window

    func testAMarkerPastTheReplayWindowIsDropped() {
        let old = marker("2026-03-01 08:00")
        let now = date("2026-03-10 08:00") // 9 days later
        XCTAssertTrue(OfflineMarkerPolicy.prune([old], now: now).isEmpty)
    }

    func testAMarkerInsideTheReplayWindowIsKept() {
        let recent = marker("2026-03-05 08:00")
        let now = date("2026-03-10 08:00") // 5 days later
        XCTAssertEqual(OfflineMarkerPolicy.prune([recent], now: now), [recent])
    }

    func testTheReplayWindowMatchesTheOtherSurfaces() {
        // edge-functions/shared/checkin-time.ts OCCURRED_AT_MAX_AGE_MS,
        // OfflineCheckInService.maxReplayAge, Android MAX_REPLAY_AGE_MS.
        XCTAssertEqual(OfflineMarkerPolicy.maxReplayAge, 7 * 24 * 60 * 60)
        XCTAssertEqual(OfflineMarkerPolicy.maxReplayAge, OfflineCheckInService.maxReplayAge)
    }

    /// A device whose clock is ahead would otherwise queue a check-in dated in
    /// the future, which the server refuses to honour.
    func testAMarkerDatedInTheFutureIsNotReplayable() {
        let future = marker("2026-03-11 08:00")
        XCTAssertFalse(OfflineMarkerPolicy.isReplayable(future, now: date("2026-03-10 08:00")))
    }

    // MARK: - Bounds and ordering

    func testPruneReturnsOldestFirst() {
        let queue = [marker("2026-03-10 08:00"), marker("2026-03-08 08:00"), marker("2026-03-09 08:00")]
        let pruned = OfflineMarkerPolicy.prune(queue, now: date("2026-03-10 09:00"))
        XCTAssertEqual(pruned.map(\.at), [date("2026-03-08 08:00"), date("2026-03-09 08:00"), date("2026-03-10 08:00")])
    }

    /// One marker per day and a seven-day window already bound the queue to 8,
    /// so `maxMarkers` is the belt rather than the braces. What is worth
    /// asserting is the bound that actually binds: a device offline for weeks
    /// cannot accumulate more than the window allows.
    func testAQueueCannotGrowBeyondTheReplayWindow() {
        var queue: [OfflineCheckInMarker] = []
        var day = date("2026-03-01 08:00")
        let end = date("2026-03-25 08:00")
        while day <= end {
            queue = OfflineMarkerPolicy.enqueue(
                queue,
                adding: OfflineCheckInMarker(at: day, type: "ok"),
                calendar: calendar,
                now: day
            )
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        XCTAssertLessThanOrEqual(queue.count, 8)
        XCTAssertLessThanOrEqual(queue.count, OfflineMarkerPolicy.maxMarkers)
    }

    // MARK: - What a glanceable surface shows

    func testYesterdaysPendingMarkerDoesNotMarkTodayDone() {
        let queue = [marker("2026-03-09 23:55")]
        XCTAssertFalse(
            OfflineMarkerPolicy.hasMarker(queue, onSameDayAs: date("2026-03-10 08:00"), calendar: calendar)
        )
    }

    func testTodaysPendingMarkerMarksTodayDone() {
        let queue = [marker("2026-03-10 08:00")]
        XCTAssertTrue(
            OfflineMarkerPolicy.hasMarker(queue, onSameDayAs: date("2026-03-10 21:00"), calendar: calendar)
        )
    }
}
