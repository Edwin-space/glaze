import XCTest

final class DiagnosticsUITests: XCTestCase {
    func testPrepareReportAndShareAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ios.onboarding.seenWelcome", "YES", "-ios.onboarding.seenGestureGuide", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        openDiagnostics(app)
        let toggle = app.switches["Record diagnostic events"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")
        app.terminate()
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        openDiagnostics(app)
        XCTAssertEqual(app.switches["Record diagnostic events"].firstMatch.value as? String, "1")
        app.buttons["Prepare diagnostic report"].tap()
        XCTAssertTrue(app.buttons["Share diagnostic report"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openDiagnostics(_ app: XCUIApplication) {
        let entry = app.buttons["diagnostics.entry"].firstMatch
        for _ in 0..<7 {
            if entry.exists, entry.isHittable { entry.tap(); return }
            app.swipeUp()
        }
        XCTFail("Diagnostics entry was not reachable")
    }
}
