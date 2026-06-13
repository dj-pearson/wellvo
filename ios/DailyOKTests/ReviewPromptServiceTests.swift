import XCTest
@testable import DailyOK

/// Tests for ReviewPromptService eligibility + throttling logic.
///
/// Note: like the other files in DailyOKTests/, these run only once a unit-test
/// target is wired into the Xcode project. The service is built to be fully
/// testable via injected UserDefaults / clock / version so no UI is involved.
@MainActor
final class ReviewPromptServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ReviewPromptServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeService(
        now: @escaping () -> Date = Date.init,
        version: String = "1.0.0",
        checkInThreshold: Int = 5,
        ownerStreakThreshold: Int = 7,
        minDaysBetweenPrompts: Int = 120
    ) -> ReviewPromptService {
        ReviewPromptService(
            defaults: defaults,
            appVersion: version,
            now: now,
            checkInThreshold: checkInThreshold,
            ownerStreakThreshold: ownerStreakThreshold,
            minDaysBetweenPrompts: minDaysBetweenPrompts
        )
    }

    // MARK: - Check-in threshold

    func testNotEligibleBeforeCheckInThreshold() {
        let service = makeService(checkInThreshold: 5)
        for _ in 0..<4 {
            XCTAssertFalse(service.registerSuccessfulCheckIn(), "Should not prompt before the 5th check-in")
        }
    }

    func testEligibleAtCheckInThreshold() {
        let service = makeService(checkInThreshold: 5)
        for _ in 0..<4 { _ = service.registerSuccessfulCheckIn() }
        XCTAssertTrue(service.registerSuccessfulCheckIn(), "The 5th check-in should make the user eligible")
    }

    // MARK: - Owner streak

    func testOwnerStreakBelowThreshold() {
        let service = makeService(ownerStreakThreshold: 7)
        XCTAssertFalse(service.shouldPromptForOwnerStreak(maxStreak: 6))
    }

    func testOwnerStreakAtThreshold() {
        let service = makeService(ownerStreakThreshold: 7)
        XCTAssertTrue(service.shouldPromptForOwnerStreak(maxStreak: 7))
    }

    // MARK: - Throttling

    func testNotEligibleTwiceOnSameVersion() {
        let service = makeService(version: "1.2.0")
        XCTAssertTrue(service.shouldPromptForOwnerStreak(maxStreak: 10))
        service.markPrompted()
        XCTAssertFalse(service.shouldPromptForOwnerStreak(maxStreak: 10),
                       "Should not ask twice on the same app version")
    }

    func testEligibleAgainOnNewVersionAfterWindow() {
        let promptDay = Date(timeIntervalSince1970: 1_700_000_000)
        let v1 = makeService(now: { promptDay }, version: "1.2.0", minDaysBetweenPrompts: 120)
        XCTAssertTrue(v1.shouldPromptForOwnerStreak(maxStreak: 10))
        v1.markPrompted()

        // 200 days later, on a new app version → eligible again.
        let later = promptDay.addingTimeInterval(200 * 86_400)
        let v2 = makeService(now: { later }, version: "1.3.0", minDaysBetweenPrompts: 120)
        XCTAssertTrue(v2.shouldPromptForOwnerStreak(maxStreak: 10))
    }

    func testNotEligibleWithinThrottleWindowEvenOnNewVersion() {
        let promptDay = Date(timeIntervalSince1970: 1_700_000_000)
        let v1 = makeService(now: { promptDay }, version: "1.2.0", minDaysBetweenPrompts: 120)
        XCTAssertTrue(v1.shouldPromptForOwnerStreak(maxStreak: 10))
        v1.markPrompted()

        // Only 30 days later: even a new version must respect the day window.
        let soon = promptDay.addingTimeInterval(30 * 86_400)
        let v2 = makeService(now: { soon }, version: "1.3.0", minDaysBetweenPrompts: 120)
        XCTAssertFalse(v2.shouldPromptForOwnerStreak(maxStreak: 10))
    }
}
