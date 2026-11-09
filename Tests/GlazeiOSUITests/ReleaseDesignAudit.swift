import XCTest

/// Capture-only release audit. Inspect every attachment before accepting it as
/// evidence. Physical-device runs must use iPhone 13 mini. Sources screens are
/// simulator-only so saved private server addresses never enter the audit report.
final class ReleaseDesignAudit: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ios.onboarding.seenWelcome", "YES", "-ios.onboarding.seenGestureGuide", "YES",
                               "-AppleLanguages", "(en)"]
    }

    func testOnboarding() {
        app.launchArguments += ["-ios.onboarding.seenWelcome", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 20))
        capture("01-welcome-top")
        app.swipeUp()
        capture("02-welcome-bottom")
    }

    func testSettings() {
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        capture("10-settings-top")
        app.swipeUp()
        capture("11-settings-middle")
        app.swipeUp()
        capture("12-settings-bottom")
        let diagnostic = app.buttons["diagnostics.entry"].firstMatch
        for _ in 0..<4 where !diagnostic.isHittable { app.swipeUp() }
        XCTAssertTrue(diagnostic.exists)
        diagnostic.tap()
        capture("13-diagnostics")
    }

    func testSettingsWithLargeText() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        capture("20-large-text-settings-top")
        app.swipeUp()
        capture("21-large-text-settings-middle")
    }

    func testKoreanSettingsAndBooks() {
        app.launchArguments += ["-AppleLanguages", "(ko)"]
        app.launch()
        app.buttons["설정"].firstMatch.tap()
        capture("22-korean-settings")
        app.buttons["서재"].firstMatch.tap()
        capture("23-korean-books")
    }

    func testSourceFormsOnSimulator() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Private saved server data must not be captured on a physical device")
        #else
        app.launch()
        app.buttons["Network"].firstMatch.tap()
        capture("30-network-start")
        let emptyAction = app.buttons["network.empty.addServer"]
        XCTAssertTrue(emptyAction.isHittable)
        emptyAction.tap()
        capture("31-source-choices")
        let webdav = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "WebDAV")).firstMatch
        XCTAssertTrue(webdav.waitForExistence(timeout: 10))
        webdav.tap()
        let address = app.textFields["webdav.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        capture("32-webdav-empty")
        address.tap()
        address.typeText("https://example.invalid:5006/video/")
        XCTAssertTrue(app.staticTexts["Address"].exists, "A filled field must retain its visible label")
        capture("33-webdav-keyboard")
        #endif
    }

    /// Seed Documents/GlazeAudit with at least two disposable sample videos first.
    /// The test only opens the named folder, never the viewer's own video library.
    func testPlaybackLayout() {
        app.launch()
        let folder = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "GlazeAudit")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 20), "Seed Documents/GlazeAudit first")
        folder.tap()
        capture("40-sample-folder")
        let film = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "AuditSample")).firstMatch
        XCTAssertTrue(film.waitForExistence(timeout: 10))
        film.tap()
        let close = app.buttons["Close player"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 20))
        let pause = app.buttons["Pause"].firstMatch
        if pause.waitForExistence(timeout: 10) { pause.tap() }
        capture("41-player-portrait-with-queue")
        let settings = app.buttons["Subtitles & Audio"].firstMatch
        XCTAssertTrue(settings.exists)
        settings.tap()
        capture("42-subtitle-sheet-medium")
        app.swipeUp()
        capture("43-subtitle-sheet-expanded")
        let delay = app.staticTexts["Delay"].firstMatch
        for _ in 0..<8 where !delay.isHittable { app.swipeUp() }
        XCTAssertTrue(delay.isHittable, "Subtitle timing must remain reachable after long track lists")
        capture("47-subtitle-adjustment-controls")
        app.buttons["Close"].firstMatch.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        capture("44-player-landscape")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
        close.tap()
    }

    func testFirstPlaybackGuideLandscape() {
        captureFirstPlaybackGuide(expectPinnedTitle: true)
    }

    func testFirstPlaybackGuideWithLargeText() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        captureFirstPlaybackGuide(expectPinnedTitle: false)
    }

    private func captureFirstPlaybackGuide(expectPinnedTitle: Bool) {
        app.launchArguments += ["-ios.onboarding.seenGestureGuide", "NO"]
        app.launch()
        let folder = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "GlazeAudit")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 20))
        folder.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "AuditSample")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 20))
        capture("45-first-playback-guide-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        capture("46-first-playback-guide-landscape")
        let done = app.buttons["player.gestureGuide.done"]
        XCTAssertTrue(done.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(done.frame), "Completion stays inside the visible screen")
        let guide = app.scrollViews["player.gestureGuide.content"]
        guide.swipeUp()
        capture("46b-first-playback-guide-landscape-scrolled")
        XCTAssertTrue(done.isHittable)
        if expectPinnedTitle {
            let title = app.staticTexts["player.gestureGuide.title"]
            XCTAssertTrue(app.windows.firstMatch.frame.contains(title.frame), "Guide heading stays visible while explanations scroll")
        }
        done.tap()
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ name: String) {
        // Accessibility idleness does not include sheet/rotation compositing.
        // Reject transitional shots; this delay is capture-only, not app logic.
        Thread.sleep(forTimeInterval: 1)
        // app.screenshot() can crop using a stale portrait accessibility frame
        // after rotation. Capture the actual device surface instead.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
