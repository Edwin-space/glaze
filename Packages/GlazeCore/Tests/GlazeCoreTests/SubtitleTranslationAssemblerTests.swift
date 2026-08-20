import Testing
@testable import GlazeCore

struct SubtitleTranslationAssemblerTests {
    private func cues() -> [SubtitleCue] {
        [
            SubtitleCue(startTime: 0, endTime: 1, text: "Hello"),
            SubtitleCue(startTime: 1, endTime: 2, text: "World"),
            SubtitleCue(startTime: 2, endTime: 3, text: "Again")
        ]
    }

    @Test func replacesTextWhenTranslatedOnly() {
        let merged = SubtitleTranslationAssembler.merge(
            cues: cues(),
            translations: [0: "안녕", 1: "세계", 2: "다시"],
            output: .translatedOnly
        )

        #expect(merged.map(\.text) == ["안녕", "세계", "다시"])
    }

    @Test func keepsSourceAboveTranslationWhenBilingual() {
        let merged = SubtitleTranslationAssembler.merge(
            cues: cues(),
            translations: [1: "세계"],
            output: .bilingual
        )

        #expect(merged[1].text == "World\n세계")
    }

    @Test func preservesTimings() {
        let merged = SubtitleTranslationAssembler.merge(
            cues: cues(),
            translations: [0: "안녕"],
            output: .translatedOnly
        )

        #expect(merged[0].startTime == 0)
        #expect(merged[0].endTime == 1)
    }

    /// A skipped line must not pull later translations onto its timestamp — the
    /// reason results are keyed by index instead of zipped.
    @Test func untranslatedCuesKeepSourceTextAndDoNotShift() {
        let merged = SubtitleTranslationAssembler.merge(
            cues: cues(),
            translations: [2: "다시"],
            output: .translatedOnly
        )

        #expect(merged.map(\.text) == ["Hello", "World", "다시"])
    }

    @Test func ignoresBlankAndUnchangedTranslations() {
        let merged = SubtitleTranslationAssembler.merge(
            cues: cues(),
            translations: [0: "   ", 1: "World"],
            output: .bilingual
        )

        #expect(merged[0].text == "Hello")
        #expect(merged[1].text == "World")
    }
}
