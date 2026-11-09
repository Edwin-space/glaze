import XCTest

final class MacReleaseDesignAudit: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStartAndSettings() {
        let app = XCUIApplication()
        // Argument-domain overrides keep private saved NAS addresses out of shots;
        // they never replace the persisted connection store.
        app.launchArguments = ["-AppleLanguages", "(en)", "-webdav.connections", "<5b5d>", "-synology.connections", "<5b5d>"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        capture("60-mac-start", app: app)
        app.typeKey(",", modifierFlags: .command)
        let subtitles = app.staticTexts["Subtitles"].firstMatch
        XCTAssertTrue(subtitles.waitForExistence(timeout: 10))
        capture("61-mac-subtitle-settings", app: app)
        for (index, title) in ["Translation", "Network", "Film information", "Keyboard", "Diagnostics"].enumerated() {
            let entry = app.staticTexts[title].firstMatch
            XCTAssertTrue(entry.exists, title)
            entry.click()
            capture("\(62 + index)-mac-\(title)", app: app)
        }
    }

    func testPlaybackAndInspectors() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        // Public XCTest URL delivery exercises Glaze's external-open route and
        // avoids the separate system file-picker process, which is not exposed
        // to this host's test accessibility session.
        app.open(URL(fileURLWithPath: "/tmp/glaze-design-audit/GlazeAudit/AuditSample1.mkv"))
        Thread.sleep(forTimeInterval: 5)
        app.typeKey(" ", modifierFlags: [])
        capture("67-mac-player", app: app)
        app.typeKey("1", modifierFlags: .command)
        capture("68-mac-subtitle-inspector", app: app)
        app.typeKey("3", modifierFlags: .command)
        capture("69-mac-media-inspector", app: app)
        Thread.sleep(forTimeInterval: 3)
        capture("69b-mac-media-inspector-settled", app: app)
        app.typeKey(" ", modifierFlags: [])
        Thread.sleep(forTimeInterval: 1)
        app.typeKey(" ", modifierFlags: [])
        capture("69c-mac-media-inspector-after-play-pause", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 1)
        let settings = app.windows["Glaze Settings"]
        let window = settings.exists ? settings : app.windows.firstMatch
        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
