import XCTest

final class ReceiverFlowTests: WellvoUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.launch()
    }

    // MARK: - Authentication

    func testReceiverCanSignIn() throws {
        guard let email = ProcessInfo.processInfo.environment["APPLE_RECEIVER_DEMO_EMAIL"],
              let password = ProcessInfo.processInfo.environment["APPLE_RECEIVER_DEMO_PASS"] else {
            XCTFail("Receiver demo credentials not set in environment")
            return
        }

        signInWithEmail(email, password: password)
        waitForAuthentication()

        // Receiver should see the check-in button (ReceiverHomeView)
        let checkInButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'check in'")
        ).firstMatch

        let checkedInStatus = app.staticTexts["You're all set!"]

        XCTAssertTrue(
            waitForElement(checkInButton, timeout: 15) || checkedInStatus.exists,
            "Receiver should see check-in button or already-checked-in status"
        )
    }

    // MARK: - Check-In Flow

    func testReceiverCanPerformCheckIn() throws {
        try signInAsReceiver()

        // Look for the big check-in button
        let checkInButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'check in'")
        ).firstMatch

        if waitForElement(checkInButton, timeout: 10) {
            checkInButton.tap()

            // After tapping, either:
            // 1. Mood selector appears (standard mode: happy, neutral, tired)
            // 2. Kid mode flow starts
            // 3. Direct check-in success
            Thread.sleep(forTimeInterval: 2)

            // Check for mood selector or success state
            let moodButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Select mood'")
            ).firstMatch

            let successText = app.staticTexts["You're all set!"]

            if moodButton.exists {
                // Select a mood
                moodButton.tap()
                Thread.sleep(forTimeInterval: 1)
            }

            // Eventually should reach success state
            XCTAssertTrue(
                waitForElement(successText, timeout: 10),
                "Should show success after check-in"
            )
        } else {
            // Already checked in today
            let checkedIn = app.staticTexts["You're all set!"]
            XCTAssertTrue(checkedIn.exists,
                          "Should show already checked in status")
        }
    }

    // MARK: - Offline Banner

    func testOfflineBannerNotShownWhenOnline() throws {
        try signInAsReceiver()

        let offlineBanner = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Offline'")
        ).firstMatch

        // Should not show offline banner when we have network
        XCTAssertFalse(offlineBanner.exists,
                       "Offline banner should not be visible when online")
    }

    // MARK: - Post Check-In State

    func testReceiverSeesCheckInConfirmation() throws {
        try signInAsReceiver()

        // Perform check-in if not already done
        let checkInButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'check in'")
        ).firstMatch

        if waitForElement(checkInButton, timeout: 5) {
            checkInButton.tap()
            Thread.sleep(forTimeInterval: 2)

            // Select mood if shown
            let moodButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Select mood'")
            ).firstMatch
            if moodButton.exists {
                moodButton.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }

        // Verify confirmation elements
        let successIcon = app.images.matching(
            NSPredicate(format: "label CONTAINS 'checkmark'")
        ).firstMatch
        let successText = app.staticTexts["You're all set!"]
        let notifiedText = app.staticTexts["Your family has been notified"]

        // At least the success text should appear
        XCTAssertTrue(
            waitForElement(successText, timeout: 10),
            "Should show 'You're all set!' after check-in"
        )
    }

    // MARK: - Private Helpers

    private func signInAsReceiver() throws {
        guard let email = ProcessInfo.processInfo.environment["APPLE_RECEIVER_DEMO_EMAIL"],
              let password = ProcessInfo.processInfo.environment["APPLE_RECEIVER_DEMO_PASS"] else {
            throw XCTSkip("Receiver demo credentials not set")
        }

        signInWithEmail(email, password: password)
        waitForAuthentication()
    }
}
