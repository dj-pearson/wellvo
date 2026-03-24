import XCTest

/// Base class for Wellvo UI tests with shared helpers.
class WellvoUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Pass demo credentials via launch environment
        app.launchEnvironment["UITEST_MODE"] = "1"

        // Credentials are injected by the CI environment or Xcode scheme
        if let ownerEmail = ProcessInfo.processInfo.environment["APPLE_OWNER_DEMO_EMAIL"] {
            app.launchEnvironment["APPLE_OWNER_DEMO_EMAIL"] = ownerEmail
        }
        if let ownerPass = ProcessInfo.processInfo.environment["APPLE_OWNER_DEMO_PASS"] {
            app.launchEnvironment["APPLE_OWNER_DEMO_PASS"] = ownerPass
        }
        if let receiverEmail = ProcessInfo.processInfo.environment["APPLE_RECEIVER_DEMO_EMAIL"] {
            app.launchEnvironment["APPLE_RECEIVER_DEMO_EMAIL"] = receiverEmail
        }
        if let receiverPass = ProcessInfo.processInfo.environment["APPLE_RECEIVER_DEMO_PASS"] {
            app.launchEnvironment["APPLE_RECEIVER_DEMO_PASS"] = receiverPass
        }
    }

    // MARK: - Helpers

    /// Wait for an element to exist with a timeout.
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Sign in using email/password via the Auth screen.
    func signInWithEmail(_ email: String, password: String) {
        // Wait for auth screen to load
        let emailToggle = app.buttons["Sign in with email instead"]
        if waitForElement(emailToggle) {
            emailToggle.tap()
        }

        // Fill in email
        let emailField = app.textFields["Email"]
        XCTAssertTrue(waitForElement(emailField), "Email field not found")
        emailField.tap()
        emailField.typeText(email)

        // Fill in password
        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(waitForElement(passwordField), "Password field not found")
        passwordField.tap()
        passwordField.typeText(password)

        // Tap Sign In
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(waitForElement(signInButton), "Sign In button not found")
        signInButton.tap()
    }

    /// Wait for the loading screen to dismiss and the main content to appear.
    func waitForAuthentication(timeout: TimeInterval = 15) {
        // Wait for the loading spinner / launch screen to disappear
        let loading = app.staticTexts["Wellvo is loading"]
        if loading.exists {
            _ = loading.waitForNonExistence(timeout: timeout)
        }
    }
}
