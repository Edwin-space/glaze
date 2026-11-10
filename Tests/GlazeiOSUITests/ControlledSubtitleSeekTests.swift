import XCTest
import UIKit

/// Public synthetic bright-grid fixture only. Never use pixel attachments with
/// a personal NAS video. Seed Documents/GlazeSeekAudit before explicitly running.
final class ControlledSubtitleSeekTests: XCTestCase {
    @MainActor
    func testNetworkAndLocalSRTRecovery() throws {
        guard ProcessInfo.processInfo.environment["GLAZE_RUN_SEEK_AUDIT"] == "1" else {
            throw XCTSkip("Seed public fixture and explicitly set TEST_RUNNER_GLAZE_RUN_SEEK_AUDIT=1")
        }
        continueAfterFailure = false
        for mode in ["network", "local-srt", "local-all"] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(en)", "-glaze.seekAudit.fixture",
                "-glaze.seekAudit.telemetry", "-ios.subtitle.automaticallySelect", "YES",
                "-diagnostics.enabled", "YES"]
            app.launchEnvironment["GLAZE_SEEK_AUDIT_CASE"] = mode
            app.launch()
            let clock = app.staticTexts["player.audit.clock"]
            XCTAssertTrue(clock.waitForExistence(timeout: 30))
            let ready = NSPredicate { _, _ in clock.label.contains("srt=1") && self.number("d", clock.label) > 0 }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 30), .completed)
            for (step, target) in [20.4, 50.4, 80.4, 50.4, 20.4, 80.4].enumerated() {
                let timeline = app.descendants(matching: .any).matching(identifier: "player.timeline").firstMatch
                if !timeline.isHittable {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
                }
                XCTAssertTrue(timeline.isHittable)
                let started = Date()
                let destination = timeline.coordinate(withNormalizedOffset: CGVector(dx: target / self.number("d", clock.label), dy: 0.5))
                if step == 1 || step == 4 {
                    timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
                        .press(forDuration: 0.4, thenDragTo: destination)
                } else {
                    destination.tap()
                }
                let settled = NSPredicate { _, _ in
                    let value = clock.label
                    return value.contains("seeking=0") && value.contains("native=0") && abs(self.number("t", value) - target) < 2.5
                        && app.staticTexts["player.sidecar.caption"].label.contains(String(format: "PROBE_%02d", Int(target / 10)))
                }
                XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: settled, evaluatedWith: nil)], timeout: 12), .completed)
                let shot = XCUIScreen.main.screenshot()
                let image = shot.image
                let fraction = try centerBlackFraction(image)
                print("SRT_CONTROL mode=\(mode) step=\(step + 1) recovery_ms=\(Int(Date().timeIntervalSince(started) * 1000)) center_black=\(fraction)")
                XCTAssertLessThan(fraction, 0.05, "Synthetic bright video was black in post-seek sample")
                if step == 0 {
                    let attachment = XCTAttachment(screenshot: shot)
                    attachment.name = "public-grid-\(mode)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            if mode == "local-all" {
                if !app.buttons["Subtitles & Audio"].isHittable {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
                }
                app.buttons["Subtitles & Audio"].tap()
                app.buttons["Off"].tap()
                app.buttons["Close"].firstMatch.tap()
                XCTAssertFalse(app.staticTexts["player.sidecar.caption"].exists)
                app.buttons["Subtitles & Audio"].tap()
                app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "player.subtitle.track.sidecar:")).firstMatch.tap()
                app.buttons["Close"].firstMatch.tap()
                XCTAssertTrue(app.staticTexts["player.sidecar.caption"].waitForExistence(timeout: 5))
                print("SRT_CONTROL visibility_toggle=1")
            }
            app.terminate()
        }
    }

    private func number(_ key: String, _ value: String) -> Double {
        let raw = value.split(separator: ";").first { $0.hasPrefix(key + "=") }
            .map { String($0.dropFirst(key.count + 1)) } ?? ""
        return Double(raw) ?? -1
    }

    /// A small center patch excludes letterboxing, captions and transport. This
    /// post-seek sample cannot rule out a single-frame flash during the gesture.
    private func centerBlackFraction(_ image: UIImage) throws -> Double {
        let cg = try XCTUnwrap(image.cgImage)
        let rect = CGRect(x: CGFloat(cg.width) * 0.45, y: CGFloat(cg.height) * 0.45,
                          width: CGFloat(cg.width) * 0.1, height: CGFloat(cg.height) * 0.1)
        let crop = try XCTUnwrap(cg.cropping(to: rect))
        var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let dark: Int = try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 32, height: 32,
                bitsPerComponent: 8, bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            let values = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: values.count, by: 4).filter {
                Int(values[$0]) + Int(values[$0 + 1]) + Int(values[$0 + 2]) < 54
            }.count
        }
        return Double(dark) / 1024
    }
}
