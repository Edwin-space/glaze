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

    private func descendToFilm(depth: Int = 0) -> XCUIElement? {
        guard depth < 5 else { return nil }
        if let film = firstFilm() { return film }
        guard let folder = firstFolder() else { return nil }
        folder.tap()
        _ = waitForFolderContents(timeout: 60)
        return descendToFilm(depth: depth + 1)
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
