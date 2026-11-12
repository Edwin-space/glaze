import Foundation
import Testing
@testable import GlazeCore

struct SubtitleLanguageAssessmentTests {
    private let japanese = "今日はとても良い天気ですね。駅まで一緒に歩いて行きましょう。明日の会議について、皆さんにお伝えしたいことがあります。"
    private let korean = "오늘은 날씨가 정말 좋네요. 역까지 같이 걸어가면 좋겠습니다. 내일 회의에 관해서 여러분에게 전달할 이야기가 있습니다."

    private func cues(_ text: String) -> [SubtitleCue] {
        (0..<6).map { .init(startTime: Double($0 * 10), endTime: Double($0 * 10 + 8), text: text) }
    }

    @Test func contentFindsJapaneseWithoutAFilenameTag() {
        let result = SubtitleLanguageAssessment.assess(cues: cues(japanese), declaredLanguageCode: nil)
        #expect(result.languageCode == "ja")
        #expect(result.origin == .content)
    }

    @Test func contentOverridesAMislabelledKoreanFile() {
        let result = SubtitleLanguageAssessment.assess(cues: cues(japanese), declaredLanguageCode: "ko")
        #expect(result.languageCode == "ja")
        #expect(result.origin == .content)
    }

    @Test func koreanTextDoesNotBecomeForeignBecauseItsNameIsEnglish() {
        let result = SubtitleLanguageAssessment.assess(cues: cues(korean), declaredLanguageCode: "en")
        #expect(result.languageCode == "ko")
    }

    @Test func shortAmbiguousTextDoesNotInventALanguage() {
        let result = SubtitleLanguageAssessment.assess(cues: cues("123 ♪ !"), declaredLanguageCode: nil)
        #expect(result.languageCode == nil)
        #expect(result.origin == .unknown)
    }

    @Test func shortTextCanStillUseAnExplicitMetadataTag() {
        let result = SubtitleLanguageAssessment.assess(cues: [], declaredLanguageCode: "jpn")
        #expect(result.languageCode == "ja")
        #expect(result.origin == .metadata)
    }

    @Test func japaneseKoreanBilingualTextIsNotCalledJapaneseOnly() {
        let result = SubtitleLanguageAssessment.assess(cues: cues(japanese + "\n" + korean), declaredLanguageCode: "ja")
        #expect(result.languageCode == nil)
        #expect(result.origin == .unknown)
    }
}
