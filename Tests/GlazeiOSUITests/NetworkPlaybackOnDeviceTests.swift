import XCTest

/// Whether a film on the NAS opens, and survives being skipped through.
///
/// The report was load times, ten-second skips and crashes — none of which can be
/// reproduced on a Mac or a simulator, because the thing under test is this phone's
/// Wi-Fi talking to that server.
///
/// Nothing here is photographed. The folders on someone's NAS are their own, and an
/// earlier run in this project proved how easily a test screenshot keeps what it
/// should not. Timings and crashes are what this reports.
final class NetworkPlaybackOnDeviceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ios.onboarding.seenWelcome", "YES",
            "-ios.onboarding.seenGestureGuide", "YES"
        ]
    }

    func testNetworkFilmOpensAndSurvivesSkipping() throws {
        app.launch()

        // iPad's tab bar reports the item twice, so an exact query is ambiguous there.
        app.buttons["네트워크"].firstMatch.tap()
        _ = app.buttons.firstMatch.waitForExistence(timeout: 15)

        if app.staticTexts[Self.noServers].exists {
            throw XCTSkip("이 기기에는 추가한 서버가 없다. 네트워크 탭에서 먼저 연결할 것.")
        }
        guard let server = firstServerRow() else {
            throw XCTSkip("저장된 서버도, 발견된 서버도 없다")
        }

        let connectStarted = Date()
        server.tap()

        guard waitForFolderContents(timeout: 60) else {
            XCTFail("서버를 열었으나 60초 안에 목록이 오지 않았다")
            return
        }
        let listed = Date().timeIntervalSince(connectStarted)
        print("NAS: 첫 폴더 목록까지 \(String(format: "%.1f", listed))초")

        // Say which way it went, so a run that wandered somewhere it should not have
        // is visible in the log rather than only in a screenshot nobody keeps.
        if let marked = markedFolder() {
            print("NAS: 표시된 폴더로 들어간다 — \(marked.label)")
        } else {
            print("NAS: 루트에 \(Self.marker) 폴더가 없다")
        }

        guard let film = descendToFilm() else {
            throw XCTSkip("서버에서 영화를 찾지 못했다")
        }

        let openStarted = Date()
        film.tap()

        // Time to the first frame: the transport only has a real duration once VLC
        // has opened the stream.
        let duration = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")
        )
        XCTAssertTrue(
            duration.firstMatch.waitForExistence(timeout: 90),
            "90초 안에 네트워크 영상이 열리지 않았다"
        )
        print("NAS: 재생 시작까지 \(String(format: "%.1f", Date().timeIntervalSince(openStarted)))초")

        let before = positionLabel()
        print("NAS: 이동 전 \(before ?? "—")")

        // The skips that were reported as crashing. Eight of them, forwards and back,
        // with no pause in between — the pattern someone uses looking for a scene.
        let forward = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        let back = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45))
        for step in 0..<8 {
            (step % 3 == 2 ? back : forward).doubleTap()
        }

        XCTAssertEqual(app.state, .runningForeground, "10초 이동 중 앱이 죽었다")

        // The controls take themselves away after five seconds, so the clock is not
        // on screen by now. That is the player working, not the player gone.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(
            duration.firstMatch.waitForExistence(timeout: 20),
            "이동 뒤 컨트롤을 다시 불러도 재생 화면이 없다"
        )
        let after = positionLabel()
        print("NAS: 이동 후 \(after ?? "—")")
        XCTAssertNotNil(after, "이동 뒤 재생 위치를 읽지 못했다")
        XCTAssertNotEqual(before, after, "10초 이동을 여덟 번 했는데 위치가 그대로다")
        print("NAS: 10초 이동 8회 뒤에도 재생 중")
    }

    /// The same film, but starting from zero.
    ///
    /// Run the other test twice and the second run hangs: the first leaves a resume
    /// position behind, and the second has to seek to it the moment the stream opens.
    /// This clears the position first. If it opens quickly while the other one does
    /// not, the seek-on-open is the thing to fix, not the network.
    func testNetworkFilmOpensQuicklyWhenThereIsNothingToResume() throws {
        app.launch()

        app.buttons["네트워크"].firstMatch.tap()
        _ = app.buttons.firstMatch.waitForExistence(timeout: 15)

        if app.staticTexts[Self.noServers].exists {
            throw XCTSkip("이 기기에는 추가한 서버가 없다")
        }
        guard let server = firstServerRow() else { throw XCTSkip("서버가 없다") }
        server.tap()
        guard waitForFolderContents(timeout: 60) else {
            XCTFail("폴더 목록이 오지 않았다")
            return
        }
        guard let film = descendToFilm() else { throw XCTSkip("영화를 찾지 못했다") }

        // Clearing the saved position through the row's hold menu was tried first and
        // the menu does not open on iPad at all — `app.menuItems` came back empty.
        // The last film in the folder serves the same purpose: the other test always
        // takes the first one, so this is one nothing has played and nothing has a
        // resume position for.
        let films = app.buttons.containing(.image, identifier: "film")
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        guard films.count > 1, let fresh = films.last else {
            throw XCTSkip("폴더에 영화가 하나뿐이라 손대지 않은 것을 고를 수 없다")
        }
        print("NAS: 한 번도 재생한 적 없는 영화로 연다 (\(films.count)개 중 마지막)")
        _ = film

        let started = Date()
        fresh.tap()

        let duration = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")
        )
        XCTAssertTrue(
            duration.firstMatch.waitForExistence(timeout: 90),
            "처음부터 재생하는데도 90초 안에 열리지 않았다"
        )
        print("NAS: 처음부터 재생 — \(String(format: "%.1f", Date().timeIntervalSince(started)))초")
    }

    /// The same film twice: once from the start, once from where it stopped.
    ///
    /// Everything else pointed here but nothing proved it, because the two films
    /// being compared were different files. This plays one, closes it so the
    /// position is written, and opens the same row again.
    func testTheSecondOpeningOfTheSameNetworkFilm() throws {
        app.launch()
        app.buttons["네트워크"].firstMatch.tap()
        _ = app.buttons.firstMatch.waitForExistence(timeout: 15)

        if app.staticTexts[Self.noServers].exists { throw XCTSkip("서버가 없다") }
        guard let server = firstServerRow() else { throw XCTSkip("서버가 없다") }
        server.tap()
        guard waitForFolderContents(timeout: 60) else {
            XCTFail("폴더 목록이 오지 않았다"); return
        }
        guard descendToFilm() != nil else { throw XCTSkip("영화를 찾지 못했다") }

        let films = app.buttons.containing(.image, identifier: "film")
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        guard let fresh = films.last else { throw XCTSkip("영화가 없다") }

        let clock = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")
        )

        // First opening.
        var started = Date()
        fresh.tap()
        XCTAssertTrue(clock.firstMatch.waitForExistence(timeout: 90), "처음 여는데 열리지 않았다")
        print("NAS: 1회차 \(String(format: "%.1f", Date().timeIntervalSince(started)))초")

        // Let it run a little so there is a position worth remembering, then close
        // the player the way a person would.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "watch")], timeout: 12)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        app.buttons.matching(.button, identifier: "chevron.down").firstMatch.tap()
        if !app.buttons.containing(.image, identifier: "film").firstMatch.waitForExistence(timeout: 10) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.05)).tap()
        }
        _ = app.buttons.containing(.image, identifier: "film").firstMatch.waitForExistence(timeout: 15)

        // Second opening — same row, now with somewhere to resume from.
        let again = app.buttons.containing(.image, identifier: "film")
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }.last
        guard let again else { XCTFail("목록으로 돌아오지 못했다"); return }
        started = Date()
        again.tap()
        let opened = clock.firstMatch.waitForExistence(timeout: 90)
        print("NAS: 2회차 \(opened ? String(format: "%.1f초", Date().timeIntervalSince(started)) : "90초 안에 안 열림")")
        XCTAssertTrue(opened, "같은 영상을 두 번째로 여니 열리지 않는다 — 이어보기 지점이 생긴 뒤")
    }

    // MARK: - Helpers

    /// The left-hand clock under the bar: where the film is now.
    private func positionLabel() -> String? {
        let clocks = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")
        ).allElementsBoundByIndex.filter { $0.exists }
        return clocks.min { $0.frame.minX < $1.frame.minX }?.label
    }

    /// A saved or discovered server, and nothing else.
    ///
    /// There used to be a fallback to "the first row, whatever it is", which on a
    /// device with no servers tapped 새 서버 and then waited a minute for a folder
    /// listing that was never coming. Three runs reported the server as unreachable
    /// when the truth was that there was no server: saved connections live in this
    /// device's own settings and Keychain, so a second device starts empty.
    private func firstServerRow() -> XCUIElement? {
        for identifier in ["externaldrive.connected.to.line.below", "tv.badge.wifi", "externaldrive"] {
            let match = app.buttons.containing(.image, identifier: identifier)
                .allElementsBoundByIndex
                .first { $0.exists && $0.isHittable && $0.label != Self.addServer }
            if let match { return match }
        }
        return nil
    }

    private static let addServer = "새 서버"
    private static let noServers = "아직 추가한 서버가 없습니다."

    private func waitForFolderContents(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if firstFilm() != nil || firstFolder() != nil { return true }
            _ = app.buttons.firstMatch.waitForExistence(timeout: 2)
        }
        return false
    }

    /// Walks down towards a film, keeping to the folders marked for testing.
    ///
    /// The owner of the server marked the ones this may use with `#1`. Everything
    /// else on a NAS is theirs, and a test that wanders into it is the same mistake
    /// that had to be cleaned up once already.
    private func descendToFilm(depth: Int = 0) -> XCUIElement? {
        guard depth < 5 else { return nil }
        if let film = firstFilm() { return film }
        guard let folder = markedFolder() ?? firstFolder() else { return nil }
        folder.tap()
        _ = waitForFolderContents(timeout: 60)
        return descendToFilm(depth: depth + 1)
    }

    private static let marker = "#1"

    private func markedFolder() -> XCUIElement? {
        app.buttons.containing(.image, identifier: "folder")
            .allElementsBoundByIndex
            .first { $0.exists && $0.isHittable && $0.label.contains(Self.marker) }
    }

    private func firstFilm() -> XCUIElement? {
        app.buttons.containing(.image, identifier: "film")
            .allElementsBoundByIndex.first { $0.exists && $0.isHittable }
    }

    private func firstFolder() -> XCUIElement? {
        app.buttons.containing(.image, identifier: "folder")
            .allElementsBoundByIndex.first { $0.exists && $0.isHittable }
    }
}
