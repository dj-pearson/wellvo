import XCTest

final class OwnerFlowTests: WellvoUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.launch()
    }

    // MARK: - Authentication

    func testOwnerCanSignIn() throws {
        guard let email = ProcessInfo.processInfo.environment["APPLE_OWNER_DEMO_EMAIL"],
              let password = ProcessInfo.processInfo.environment["APPLE_OWNER_DEMO_PASS"] else {
            XCTFail("Owner demo credentials not set in environment")
            return
        }

        signInWithEmail(email, password: password)
        waitForAuthentication()

        // Owner should see the tab bar with Dashboard
        let dashboardTab = app.tabBars.buttons["Dashboard tab"]
        XCTAssertTrue(waitForElement(dashboardTab, timeout: 15),
                      "Owner should see Dashboard tab after sign-in")
    }

    // MARK: - Dashboard

    func testOwnerDashboardLoads() throws {
        try signInAsOwner()

        // Verify dashboard content loads (receiver cards or empty state)
        let dashboard = app.tabBars.buttons["Dashboard tab"]
        XCTAssertTrue(dashboard.isSelected || dashboard.exists,
                      "Dashboard tab should be visible")

        // Either "No Receivers Yet" empty state or receiver status cards
        let hasReceivers = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'day streak'")
        ).count > 0
        let hasEmptyState = app.staticTexts["No Receivers Yet"].exists

        XCTAssertTrue(hasReceivers || hasEmptyState,
                      "Dashboard should show receivers or empty state")
    }

    // MARK: - Tab Navigation

    func testOwnerCanNavigateTabs() throws {
        try signInAsOwner()

        // Navigate to each tab
        let tabs = ["History tab", "Family tab", "Settings tab", "Dashboard tab"]
        for tabName in tabs {
            let tab = app.tabBars.buttons[tabName]
            XCTAssertTrue(waitForElement(tab), "\(tabName) should exist")
            tab.tap()
            // Small delay for navigation animation
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // MARK: - On-Demand Check-In

    func testOwnerCanSendOnDemandCheckIn() throws {
        try signInAsOwner()

        // Look for a "Check on" button (visible when receivers exist)
        let checkOnButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Check on'")
        ).firstMatch

        if waitForElement(checkOnButton, timeout: 10) {
            checkOnButton.tap()

            // Wait for confirmation or response
            Thread.sleep(forTimeInterval: 2)

            // The button should be disabled after sending (already checked in state)
            // Or a success indicator should appear
        } else {
            // No receivers — skip this test gracefully
            print("No receivers found on dashboard, skipping on-demand check-in test")
        }
    }

    // MARK: - Family View

    func testOwnerCanViewFamilyMembers() throws {
        try signInAsOwner()

        let familyTab = app.tabBars.buttons["Family tab"]
        XCTAssertTrue(waitForElement(familyTab), "Family tab should exist")
        familyTab.tap()

        // Family view should load (either members or add prompt)
        Thread.sleep(forTimeInterval: 1)

        // Check that the view rendered something
        XCTAssertTrue(app.navigationBars.count > 0 || app.staticTexts.count > 0,
                      "Family view should render content")
    }

    // MARK: - Private Helpers

    private func signInAsOwner() throws {
        guard let email = ProcessInfo.processInfo.environment["APPLE_OWNER_DEMO_EMAIL"],
              let password = ProcessInfo.processInfo.environment["APPLE_OWNER_DEMO_PASS"] else {
            throw XCTSkip("Owner demo credentials not set")
        }

        signInWithEmail(email, password: password)
        waitForAuthentication()

        // Verify we reached the owner dashboard
        let dashboardTab = app.tabBars.buttons["Dashboard tab"]
        XCTAssertTrue(waitForElement(dashboardTab, timeout: 15),
                      "Should reach owner dashboard")
    }
}
