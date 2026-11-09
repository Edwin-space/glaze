import XCTest
@testable import GlazeCore

final class ReleasePresentationTests: XCTestCase {
    func testLanguageNamesFollowAppLanguageRatherThanRegionalLocale() {
        XCTAssertEqual(L10n.languageName(for: "eng", preferredLanguages: ["en-KR"]), "English")
        XCTAssertEqual(L10n.languageName(for: "en", preferredLanguages: ["ko-US"]), "영어")
        XCTAssertEqual(L10n.languageName(for: "deu", preferredLanguages: ["en"]), "German")
        XCTAssertEqual(L10n.languageName(for: "en", preferredLanguages: ["fr-FR"]), "English")
        XCTAssertNil(L10n.languageName(for: "und", preferredLanguages: ["en"]))
        XCTAssertEqual(L10n.displayLanguageCode(for: ["ko_KR"]), "ko")
        XCTAssertEqual(L10n.displayLanguageCode(for: []), "en")
    }

    func testContainerAliasesDoNotTurnEveryMatroskaFileIntoWebM() {
        XCTAssertEqual(MediaContainerName.displayName(formatNames: "matroska,webm", pathExtension: "mkv"), "Matroska")
        XCTAssertEqual(MediaContainerName.displayName(formatNames: "matroska,webm", pathExtension: "webm"), "WebM")
        XCTAssertEqual(MediaContainerName.displayName(formatNames: "matroska,webm", pathExtension: ""), "Matroska / WebM")
        XCTAssertEqual(MediaContainerName.displayName(formatNames: "avi", pathExtension: "mkv"), "AVI")
        XCTAssertEqual(MediaContainerName.displayName(formatNames: nil, pathExtension: "mp4"), "MP4")
        XCTAssertEqual(MediaContainerName.displayName(formatNames: nil, pathExtension: ""), "–")
    }
}
