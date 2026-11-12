import XCTest

/// Explicit public-fixture audit. No personal video, NAS listing or subtitle is
/// captured. Uses the real external-open, sidecar loader and consent sheet.
final class AutomaticSubtitleTranslationTests: XCTestCase {
    private let japanese = "今日はとても良い天気ですね。駅まで一緒に歩いて行きましょう。明日の会議について、皆さんにお伝えしたいことがあります。"
    private let korean = "오늘은 날씨가 정말 좋네요. 역까지 같이 걸어가면 좋겠습니다. 내일 회의에 관해서 여러분에게 전달할 이야기가 있습니다."

    @MainActor func testSameNameJapaneseSubtitleOffersKoreanWithoutStartingWork() throws {
        try checkOffer(text: japanese, suffix: "srt", expectedOffer: true)
    }

    @MainActor func testMislabelledKoreanFilenameIsDetectedAsJapanese() throws {
        try checkOffer(text: japanese, suffix: "ko.srt", expectedOffer: true)
    }

    @MainActor func testKoreanContentDoesNotPromptEvenWithEnglishFilename() throws {
        try checkOffer(text: korean, suffix: "en.srt", expectedOffer: false)
    }

    @MainActor func testConsentTranslatesJapaneseIntoANewKoreanFile() throws {
        try checkOffer(text: japanese, suffix: "ko.srt", expectedOffer: true, confirmTranslation: true)
    }

    @MainActor private func checkOffer(text: String, suffix: String, expectedOffer: Bool, confirmTranslation: Bool = false) throws {
        guard let path = ProcessInfo.processInfo.environment["GLAZE_LANGUAGE_AUDIT_VIDEO"] else {
            throw XCTSkip("Supply a public video in TEST_RUNNER_GLAZE_LANGUAGE_AUDIT_VIDEO")
        }
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glaze-language-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("LanguageAudit.mp4")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: video)
        let original = (0..<5).map { index in
            "\(index + 1)\n00:00:\(String(format: "%02d", index * 3)),000 --> 00:00:\(String(format: "%02d", index * 3 + 2)),800\n\(text)\n"
        }.joined(separator: "\n")
        let source = folder.appendingPathComponent("LanguageAudit.\(suffix)")
        try original.write(to: source, atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-subtitle.translationTargetLanguage", "ko",
            "-subtitle.autoTranslation", "ask", "-subtitle.translationEngine", "appleTranslation"]
        app.launch()
        app.open(video)
        let decline = app.buttons["subtitle.auto_translate.decline"]
        if expectedOffer {
            XCTAssertTrue(decline.waitForExistence(timeout: 20))
            // AppKit may combine adjacent SwiftUI Text nodes into one AX text.
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "한국어로 번역할까요?")).firstMatch.exists)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", source.lastPathComponent)).firstMatch.exists)
            let language = app.popUpButtons["subtitle.auto_translate.source_language"]
            XCTAssertTrue(language.exists)
            XCTAssertTrue((language.value as? String ?? language.label).contains("일본어"))
            XCTAssertTrue(app.buttons["subtitle.auto_translate.whileWatching"].exists)
            XCTAssertTrue(app.buttons["subtitle.auto_translate.beforeWatching"].exists)
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = "public-auto-translation-\(suffix)"
            shot.lifetime = .keepAlways
            add(shot)
            // No consent, no generated files. Choosing the original dismisses once.
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
            if confirmTranslation {
                app.buttons["subtitle.auto_translate.beforeWatching"].click()
                let output = folder.appendingPathComponent("LanguageAudit.translated-1.ko.srt")
                let saved = NSPredicate { _, _ in FileManager.default.fileExists(atPath: output.path) }
                XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: saved, evaluatedWith: nil)], timeout: 90), .completed)
                let translated = try String(contentsOf: output, encoding: .utf8)
                XCTAssertTrue(translated.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) })
                XCTAssertTrue(translated.contains("00:00:00,000 --> 00:00:02,800"))
                print("AUTO_SUBTITLE consent_translation_saved=1 original_preserved=1")
            } else {
                decline.click()
                XCTAssertFalse(decline.waitForExistence(timeout: 2))
            }
        } else {
            XCTAssertFalse(decline.waitForExistence(timeout: 5))
            app.typeKey("1", modifierFlags: .command)
            XCTAssertTrue(app.popUpButtons.firstMatch.waitForExistence(timeout: 5))
        }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }
}
