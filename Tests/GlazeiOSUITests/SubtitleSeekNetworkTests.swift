import XCTest

/// Run only on the viewer-authorized iPhone 13 mini. Raw XCTest results remain
/// local: framework failure attachments may contain NAS names or a video frame.
/// Never add screenshots, filenames, server addresses or subtitle text to reports.
final class SubtitleSeekNetworkTests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor private func configure() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)",
            "-ios.onboarding.seenWelcome", "YES", "-ios.onboarding.seenGestureGuide", "YES",
            "-ios.subtitle.automaticallySelect", "YES", "-ios.browse.layout", "list",
            "-glaze.playbackLog", "NO", "-diagnostics.enabled", "YES", "-glaze.seekAudit.telemetry"]
    }

    @MainActor func testAuthorizedSynologyDramaSRTSeeking() throws {
        guard let title = ProcessInfo.processInfo.environment["GLAZE_NAS_AUDIT_TITLE"] else {
            throw XCTSkip("Supply an explicitly authorized title through TEST_RUNNER_GLAZE_NAS_AUDIT_TITLE")
        }
        XCTAssertFalse(title.isEmpty)
        configure()
        app.launch()
        app.buttons["네트워크"].firstMatch.tap()
        let synology = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Synology")).firstMatch
        XCTAssertTrue(synology.waitForExistence(timeout: 15), "No saved Synology connection on authorized phone")
        synology.tap()
        let drama = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "드라마")).firstMatch
        if drama.waitForExistence(timeout: 30) {
            drama.tap()
        } else {
            // Some saved roots begin inside the drama share. Do not browse another
            // named library on a guess: the test stops unless that root is explicit.
            XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "드라마")).firstMatch.exists,
                          "Authorized drama folder was not found at saved root")
        }
        XCTAssertTrue(findTitleFolder(title), "Requested title folder not found in authorized drama subtree")
        print("SRT_NAS title_scope=1")
        foldersVisited = 0
        let chosen = try XCTUnwrap(findSRTFilm(), "No SRT video within bounded authorized drama subtree")
        chosen.tap()
        let clock = app.staticTexts["player.audit.clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 60), "Playback view did not open")
        print("SRT_NAS candidates=\(Int(number("candidates", in: clock.label)))")
        if !clock.label.contains("srt=1"), number("candidates", in: clock.label) > 0 {
            let settings = app.buttons["자막과 음성"].firstMatch
            if settings.waitForExistence(timeout: 5) {
                settings.tap()
                let srt = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", ".srt")).firstMatch
                if srt.waitForExistence(timeout: 10) { srt.tap() }
                app.buttons["닫기"].firstMatch.tap()
            }
        }
        let ready = NSPredicate { _, _ in
            clock.label.contains("srt=1") && self.number("d", in: clock.label) > 0
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 45), .completed,
                       "No locally prepared SRT for chosen film")
        let state = clock.label
        let duration = number("d", in: state)
        let targets = field("targets", in: state).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(targets.count, 3)
        var visibleRecoveries = 0
        for (index, target) in (targets + targets.reversed()).enumerated() {
            XCTAssertGreaterThan(target, 0)
            XCTAssertLessThan(target, duration)
            revealControls()
            let timeline = app.descendants(matching: .any).matching(identifier: "player.timeline").firstMatch
            XCTAssertTrue(timeline.isHittable)
            let liveDuration = number("d", in: clock.label)
            // A long film's short cue can be narrower than one screen point.
            // Judge the actual landing time, including a genuine subtitle gap,
            // not an unattainable subpixel target on the physical timeline.
            let tolerance = max(2.5, liveDuration / timeline.frame.width + 2)
            let point = timeline.coordinate(withNormalizedOffset: CGVector(dx: target / liveDuration, dy: 0.5))
            let began = Date()
            point.tap()
            let settled = NSPredicate { _, _ in
                let value = clock.label
                let active = self.number("active", in: value) > 0
                return value.contains("seeking=0") && value.contains("native=0")
                    && abs(self.number("t", in: value) - target) < tolerance
                    && self.app.staticTexts["player.sidecar.caption"].exists == active
            }
            let done = expectation(for: settled, evaluatedWith: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 12), .completed,
                           "Seek did not regain its mid-cue SRT within timeout")
            if app.staticTexts["player.sidecar.caption"].exists { visibleRecoveries += 1 }
            print("SRT_SEEK step=\(index + 1) recovery_ms=\(Int(Date().timeIntervalSince(began) * 1000)) target=\(target) actual=\(number("t", in: clock.label)) active=\(Int(number("active", in: clock.label)))")
        }
        XCTAssertGreaterThan(visibleRecoveries, 0, "All landings were empty; subtitle visibility remains unverified")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private var foldersVisited = 0

    /// The requested title is supplied only at execution, not retained in source
    /// or application diagnostics. No film is opened while locating its folder.
    @MainActor private func findTitleFolder(_ title: String, depth: Int = 0) -> Bool {
        guard depth < 4, foldersVisited < 16 else { return false }
        foldersVisited += 1
        let folders = app.buttons.containing(.image, identifier: "folder")
        guard folders.firstMatch.waitForExistence(timeout: 15) else { return false }
        if let match = folders.allElementsBoundByIndex.first(where: { $0.label.localizedCaseInsensitiveContains(title) }) {
            match.tap()
            return true
        }
        let count = min(folders.count, 8)
        for index in 0..<count {
            folders.element(boundBy: index).tap()
            if findTitleFolder(title, depth: depth + 1) { return true }
            app.navigationBars.buttons.firstMatch.tap()
        }
        return false
    }

    @MainActor private func findSRTFilm(depth: Int = 0) -> XCUIElement? {
        guard depth < 5, foldersVisited < 16 else { return nil }
        foldersVisited += 1
        let movies = app.buttons.containing(.image, identifier: "film")
        let folders = app.buttons.containing(.image, identifier: "folder")
        let loaded = NSPredicate { _, _ in movies.firstMatch.exists || folders.firstMatch.exists }
        guard XCTWaiter.wait(for: [expectation(for: loaded, evaluatedWith: nil)], timeout: 15) == .completed else { return nil }
        if let film = movies.allElementsBoundByIndex.first(where: {
            let value = $0.value as? String ?? ""
            return value.hasPrefix("srt=") && value != "srt=0"
        }) { return film }
        let count = min(folders.count, 6)
        for index in 0..<count {
            folders.element(boundBy: index).tap()
            if let found = findSRTFilm(depth: depth + 1) { return found }
            app.navigationBars.buttons.firstMatch.tap()
        }
        return nil
    }

    @MainActor private func revealControls() {
        if !app.descendants(matching: .any).matching(identifier: "player.timeline").firstMatch.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        }
    }

    private func field(_ key: String, in value: String) -> String {
        value.split(separator: ";").first { $0.hasPrefix(key + "=") }
            .map { String($0.dropFirst(key.count + 1)) } ?? ""
    }

    private func number(_ key: String, in value: String) -> Double { Double(field(key, in: value)) ?? -1 }
}
