import XCTest

/// The pictures the App Store listing is made of.
///
/// Not a test of anything — a way of taking the same screenshots the same way every
/// time, from the app actually running, so the listing never drifts from the product.
///
/// It runs against a simulator rather than the phone on purpose. Apple asks for a
/// 6.9-inch iPhone (1320×2868) and a 13-inch iPad (2064×2752); the real devices here
/// are a 6.3-inch iPhone and an 8.3-inch iPad mini, so neither can produce a picture
/// of the required size. The simulator runs the same build.
///
/// The film is Sintel, © Blender Foundation, CC BY 3.0 — chosen because the listing
/// is published and the test library is not ours to show. Put it in place with:
///
///   xcrun simctl addmedia <device> "test file/Sintel.2010.1080p.mkv"
///
/// or by copying it into the simulator's Documents container as "Sintel (2010).mkv".
final class StoreScreenshots: XCTestCase {
    private var app: XCUIApplication!

    static let filmName = "Sintel"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ios.onboarding.seenWelcome", "YES",
            "-ios.onboarding.seenGestureGuide", "YES"
        ]
    }

    func testTakeThem() {
        app.launch()

        let film = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", Self.filmName)
        ).firstMatch
        XCTAssertTrue(
            film.waitForExistence(timeout: 20),
            "시뮬레이터에 Sintel이 없다. addmedia로 넣고 다시 실행할 것."
        )

        shoot("01-library")

        film.tap()
        // Long enough for VLC to have a picture rather than a black frame.
        let clock = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")
        )
        XCTAssertTrue(clock.firstMatch.waitForExistence(timeout: 30), "영상이 열리지 않았다")
        seek(toFraction: 0.33)
        // A seek lands before the decoder does. Shooting straight away gave a black
        // rectangle where the film should be.
        settle(seconds: 4)
        revealControls()
        shoot("02-player")

        // The subtitle picker: Sintel carries several subtitle tracks, which is the
        // point of the shot.
        // The chrome takes itself away after five seconds, and the settle above
        // spends four of them.
        revealControls()
        // By position rather than by name: the control is the last disc on the top
        // row, and querying it by label came back empty twice while it was plainly
        // on screen in the shot taken a second earlier.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.916, dy: 0.098)).tap()
        settle(seconds: 2)
        shoot("03-subtitles")
        let close = app.buttons["닫기"].firstMatch
        if close.exists { close.tap() } else { app.swipeDown() }
        settle(seconds: 1)

        revealControls()
        let shots = MidDragShots()
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            shots.add(XCUIScreen.main.screenshot())
        }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.896))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.896))
        from.press(forDuration: 0.5, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 6.0)
        for (index, shot) in shots.all().enumerated() {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "04-scrub-\(index + 1)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    // MARK: - Helpers

    private func seek(toFraction fraction: Double) {
        revealControls()
        app.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.896)).tap()
    }

    /// Waits without asserting. `waitForExistence` needs something to wait for, and
    /// what is being waited on here is a picture.
    private func settle(seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    private func revealControls() {
        let clock = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")
        )
        guard !clock.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        _ = clock.firstMatch.waitForExistence(timeout: 5)
    }

    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private final class MidDragShots: @unchecked Sendable {
        private let lock = NSLock()
        private var shots: [XCUIScreenshot] = []
        func add(_ shot: XCUIScreenshot) { lock.lock(); shots.append(shot); lock.unlock() }
        func all() -> [XCUIScreenshot] { lock.lock(); defer { lock.unlock() }; return shots }
    }
}
