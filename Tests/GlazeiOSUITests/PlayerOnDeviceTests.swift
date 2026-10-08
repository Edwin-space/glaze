import XCTest

/// What only a real phone can answer.
///
/// Three things in this file have already been got wrong on the simulator and only
/// shown up on hardware: the scrub preview came back black, a slow drag along the
/// timeline also engaged the press-and-hold speed, and the first-run cards had never
/// been seen on a device at all. VLC decodes with the hardware here and not there,
/// and a finger is not a synthetic touch, so these are checked where they are used.
///
/// The test also leaves a screenshot at each step. They are the App Store pictures,
/// taken from the real thing rather than mocked up.
final class PlayerOnDeviceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // UserDefaults reads the argument domain first, so the app starts as it does
        // for somebody who has just installed it — without touching what is actually
        // stored on the phone.
        app.launchArguments = [
            "-ios.onboarding.seenWelcome", "NO",
            "-ios.onboarding.seenGestureGuide", "NO"
        ]
    }

    // MARK: - First run

    func testFirstRunCardsAppearAndCanBeDismissed() {
        app.launch()

        let start = app.buttons["시작하기"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "첫 실행 카드가 뜨지 않았다")
        attach(name: "01-welcome")

        start.tap()

        let library = app.staticTexts["로컬"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "카드를 닫아도 로컬 목록이 보이지 않았다")
        attach(name: "02-library")
    }

    // MARK: - The player

    func testGestureGuideThenScrubPreviewWithoutRunawaySpeed() {
        app.launch()

        if app.buttons["시작하기"].waitForExistence(timeout: 20) {
            app.buttons["시작하기"].tap()
        }

        openSampleFilm()

        // The gestures card, over the first film ever opened.
        let gotIt = app.buttons["알겠습니다"]
        XCTAssertTrue(gotIt.waitForExistence(timeout: 20), "손동작 안내가 뜨지 않았다")
        attach(name: "03-gesture-guide")
        gotIt.tap()

        // The controls come up with the film; a tap puts them back if they have gone.
        revealControlsIfNeeded()
        attach(name: "04-player")

        // Hold at the end of the drag so the preview is still on screen when the
        // screenshot is taken. Everything about this gesture is the thing being
        // tested: slow, along the bar, and long enough to have been read as a
        // press-and-hold before the fix.
        // Looked for while the finger is still down. Checking afterwards proves
        // nothing: the badge goes as soon as the hold is released, so the first
        // version of this test passed over a bug that was plainly on screen.
        let watcher = SpeedBadgeWatcher(app: app)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { watcher.look() }

        let bar = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.896))
        let further = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.896))
        bar.press(
            forDuration: 0.6,
            thenDragTo: further,
            withVelocity: .slow,
            thenHoldForDuration: 6.0
        )
        let sawSpeedBadge = watcher.saw

        attach(name: "05-scrub-preview")
        XCTAssertFalse(sawSpeedBadge, Self.speedBadgeFailure)
    }

    static let speedBadgeFailure = """
        재생 막대를 끄는 동안 배속 표시가 떴다 — 길게 누르기가 같이 걸렸다.
        손을 뗀 뒤에 확인하면 이미 사라져 있으므로 끄는 도중에 봐야 한다.
        """

    /// The preview card, photographed while the finger is still on the bar.
    ///
    /// This is the only thing in the file that needed thought. A gesture blocks the
    /// test until it finishes, and by then the preview is gone — the screenshot
    /// XCUITest takes afterwards shows a plain player and proves nothing. Capturing
    /// from the Mac alongside the run was worse: `devicectl` and the test could not
    /// be made to agree on when the drag was happening, and the phone slept through
    /// two attempts.
    ///
    /// So the screenshot is scheduled before the gesture starts and fires from
    /// another queue while the drag is held. The test thread is busy dragging; this
    /// one only reads the screen.
    func testScrubPreviewShowsAFrameWhileTheFingerIsDown() {
        app.launchArguments += ["-ios.onboarding.seenGestureGuide", "YES"]
        app.launch()

        if app.buttons["시작하기"].waitForExistence(timeout: 20) {
            app.buttons["시작하기"].tap()
        }
        openSampleFilm()
        revealControlsIfNeeded()

        let shots = MidDragShots()
        // Two moments inside the hold, so a single unlucky frame — taken while the
        // thumbnailer is still decoding — cannot be mistaken for a feature that does
        // not work.
        for delay in [3.0, 6.0] {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                shots.add(XCUIScreen.main.screenshot())
            }
        }

        let bar = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.896))
        let further = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.896))
        bar.press(
            forDuration: 0.6,
            thenDragTo: further,
            withVelocity: .slow,
            thenHoldForDuration: 8.0
        )

        let taken = shots.all()
        XCTAssertEqual(taken.count, 2, "끄는 중 화면을 찍지 못했다")
        for (index, shot) in taken.enumerated() {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "09-scrub-while-dragging-\(index + 1)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Reads the screen for the 2x badge from another queue, because the thread
    /// that could ask is busy performing the drag.
    private final class SpeedBadgeWatcher: @unchecked Sendable {
        private let app: XCUIApplication
        private let lock = NSLock()
        private var seen = false

        init(app: XCUIApplication) { self.app = app }

        func look() {
            let found = app.staticTexts.matching(
                NSPredicate(format: "label ENDSWITH %@", "속도")
            ).count > 0
            lock.lock()
            seen = seen || found
            lock.unlock()
        }

        var saw: Bool {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }
    }

    /// Screenshots taken off the test thread, collected for attaching once the
    /// gesture that was blocking it has finished.
    private final class MidDragShots: @unchecked Sendable {
        private let lock = NSLock()
        private var shots: [XCUIScreenshot] = []

        func add(_ shot: XCUIScreenshot) {
            lock.lock()
            defer { lock.unlock() }
            shots.append(shot)
        }

        func all() -> [XCUIScreenshot] {
            lock.lock()
            defer { lock.unlock() }
            return shots
        }
    }

    // MARK: - Film information

    /// The whole point of the information screen: ask TMDB, get more than one answer,
    /// and let the viewer pick. Nothing is applied — this reads, it does not write.
    func testLookingUpAFilmReturnsSeveralAnswersToChooseFrom() {
        app.launch()

        if app.buttons["시작하기"].waitForExistence(timeout: 20) {
            app.buttons["시작하기"].tap()
        }

        let row = sampleRow()
        XCTAssertTrue(row.waitForExistence(timeout: 20), Self.missingSample)
        row.swipeLeft()
        app.buttons["영상 정보"].tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "검색어 칸이 없다")

        // Put the cursor at the end of what is there, then take it out a character
        // at a time. The select-all menu was tried first and silently did nothing,
        // which turned the search into "glaze-uitest-sampleParasite" — a query that
        // correctly found nothing, while the test called it a pass.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4))
        // An empty SwiftUI text field reports its placeholder as its value, so
        // "찾을 제목" is what empty looks like from here.
        let afterClearing = (field.value as? String) ?? ""
        XCTAssertTrue(
            afterClearing.isEmpty || afterClearing == "찾을 제목",
            "검색어 칸을 비우지 못했다: \(afterClearing)"
        )

        // A title with well-known near-matches, so one result would be the
        // suspicious outcome rather than the good one.
        field.typeText("Parasite")

        app.buttons["정보 다시 찾기"].tap()

        let results = app.staticTexts["검색 결과"]
        XCTAssertTrue(
            results.waitForExistence(timeout: 30),
            "TMDB 검색 결과가 오지 않았다 — 키가 없거나 네트워크가 막혔다"
        )
        attach(name: "08-tmdb-results")

        // "검색 결과" appears whether or not anything matched, so the header alone
        // proves nothing.
        XCTAssertFalse(
            app.staticTexts[Self.nothingMatched].exists,
            "TMDB가 아무것도 돌려주지 않았다"
        )
        XCTAssertGreaterThanOrEqual(
            resultRowCount(), 2,
            "후보가 하나뿐이다 — 고를 것이 있어야 선택 화면에 뜻이 있다"
        )
    }

    private static let nothingMatched = "맞는 작품을 찾지 못했습니다. 제목을 바꿔서 다시 찾아보세요."

    /// Rows under 검색 결과: each is a button carrying a poster and a title.
    private func resultRowCount() -> Int {
        app.buttons.allElementsBoundByIndex.filter { button in
            guard button.exists else { return false }
            let label = button.label
            return !label.isEmpty
                && label != "닫기"
                && label != "정보 다시 찾기"
                && !label.contains(Self.sampleName)
        }.count
    }


    func testFilmInformationOpensFromTheSwipe() {
        app.launch()

        if app.buttons["시작하기"].waitForExistence(timeout: 20) {
            app.buttons["시작하기"].tap()
        }

        let row = sampleRow()
        XCTAssertTrue(row.waitForExistence(timeout: 20), Self.missingSample)
        row.swipeLeft()
        attach(name: "06-swipe-action")

        let info = app.buttons["영상 정보"]
        XCTAssertTrue(info.waitForExistence(timeout: 5), "밀어도 영상 정보가 나오지 않았다")
        info.tap()

        XCTAssertTrue(
            app.staticTexts["지금 기록된 정보"].waitForExistence(timeout: 10),
            "영상 정보 화면이 열리지 않았다"
        )
        attach(name: "07-film-information")
    }

    // MARK: - Helpers

    /// The one film this test is allowed to open.
    ///
    /// An earlier run opened whatever was first in the folder, which on a real phone
    /// is somebody's own library — and the screenshots it took had to be destroyed.
    /// A test that drives a device drives it over a file the test put there, never
    /// over what it found.
    ///
    /// Put in place with:
    ///   devicectl device copy to --domain-type appDataContainer
    ///     --domain-identifier com.edwin.glaze
    ///     --source "test file/testmedia.mkv"
    ///     --destination Documents/glaze-uitest-sample.mkv
    static let sampleName = "glaze-uitest-sample"
    static let missingSample = """
        기기에 \(sampleName).mkv가 없다. devicectl device copy to로         Documents에 넣고 다시 실행할 것. 이 테스트는 사용자의 영상을 열지 않는다.
        """

    private func sampleRow() -> XCUIElement {
        app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", Self.sampleName)
        ).firstMatch
    }

    private func openSampleFilm() {
        let row = sampleRow()
        XCTAssertTrue(row.waitForExistence(timeout: 20), Self.missingSample)
        row.tap()
    }

    private func revealControlsIfNeeded() {
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if !app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")
        ).firstMatch.exists {
            middle.tap()
        }
    }

    private func attach(name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
