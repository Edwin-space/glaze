import XCTest

/// Simulator-only audit. Never deploys to the viewer's Apple TV.
final class TVReleaseDesignAudit: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("This audit is authorized for an Apple TV simulator only")
        #endif
    }

    func testOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-tv.onboarding.completed", "NO"]
        app.launch()
        let next = app.buttons["Continue"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        capture("70-tv-welcome", app: app)
        XCUIRemote.shared.press(.select)
        capture("71-tv-subtitle-language", app: app)
        if !next.hasFocus { XCUIRemote.shared.press(.down) }
        if !next.hasFocus { XCUIRemote.shared.press(.right) }
        XCTAssertTrue(next.hasFocus, "Continue must be reachable with the remote")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Start Glaze"].waitForExistence(timeout: 20))
        capture("72-tv-source-setup", app: app)
    }

    func testHomeAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-tv.onboarding.completed", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        capture("73-tv-home", app: app)
        let settings = app.buttons["Settings"].firstMatch
        for _ in 0..<6 where !settings.hasFocus { XCUIRemote.shared.press(.up) }
        for _ in 0..<8 where !settings.hasFocus { XCUIRemote.shared.press(.right) }
        XCTAssertTrue(settings.hasFocus, "Settings must be reachable from the tab bar")
        XCUIRemote.shared.press(.select)
        capture("74-tv-settings", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 2)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
