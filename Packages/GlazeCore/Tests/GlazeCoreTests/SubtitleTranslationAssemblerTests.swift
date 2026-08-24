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

    private func singleCueSegments(_ count: Int, from cues: [SubtitleCue]) -> [SubtitleSegment] {
        (0..<count).map { SubtitleSegment(cueIndices: [$0], text: cues[$0].text) }
    }

    @Test func replacesTextWhenTranslatedOnly() {
        let cues = cues()
        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: singleCueSegments(3, from: cues),
            translations: ["안녕", "세계", "다시"],
            output: .translatedOnly,
            targetLanguageCode: "ko"
        )

        #expect(assembled.map(\.text) == ["안녕", "세계", "다시"])
    }

    @Test func keepsSourceAboveTranslationWhenBilingual() {
        let cues = cues()
        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: singleCueSegments(3, from: cues),
            translations: [nil, "세계", nil],
            output: .bilingual,
            targetLanguageCode: "ko"
        )

        #expect(assembled[1].text == "World\n세계")
    }

    @Test func preservesTimings() {
        let cues = cues()
        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: singleCueSegments(3, from: cues),
            translations: ["안녕", nil, nil],
            output: .translatedOnly,
            targetLanguageCode: "ko"
        )

        #expect(assembled[0].startTime == 0)
        #expect(assembled[0].endTime == 1)
    }

    /// A segment the engine skipped keeps its source text, and must not pull later
    /// translations onto its timestamp.
    @Test func untranslatedSegmentsKeepSourceTextAndDoNotShift() {
        let cues = cues()
        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: singleCueSegments(3, from: cues),
            translations: [nil, nil, "다시"],
            output: .translatedOnly,
            targetLanguageCode: "ko"
        )

        #expect(assembled.map(\.text) == ["Hello", "World", "다시"])
    }

    /// A sentence spanning two cues is translated once and split back across both.
    @Test func distributesAMultiCueSegmentBackOntoItsCues() {
        let cues = [
            SubtitleCue(startTime: 0, endTime: 1, text: "I didn't leave"),
            SubtitleCue(startTime: 1, endTime: 2, text: "because he asked me to.")
        ]
        let segments = [
            SubtitleSegment(cueIndices: [0, 1], text: "I didn't leave because he asked me to.")
        ]

        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: segments,
            translations: ["그가 부탁했기 때문에 나는 떠나지 않았어요."],
            output: .translatedOnly,
            targetLanguageCode: "ko"
        )

        #expect(assembled.count == 2)
        #expect(assembled[0].text != cues[0].text)
        #expect(assembled[1].text != cues[1].text)
        #expect(assembled[0].endTime == 1)
        #expect(assembled[1].startTime == 1)
    }

    /// Guards against an engine echoing its prompt or rambling: wildly mismatched
    /// output is discarded in favour of the source.
    @Test func rejectsTranslationsWithImplausibleLength() {
        #expect(!SubtitleTranslationAssembler.isUsable(
            translated: String(repeating: "말 ", count: 200),
            source: "Hi."
        ))
        #expect(!SubtitleTranslationAssembler.isUsable(translated: "  ", source: "Hello"))
        #expect(SubtitleTranslationAssembler.isUsable(translated: "안녕하세요", source: "Hello"))
    }

    @Test func ignoresTranslationsIdenticalToSource() {
        let cues = cues()
        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: singleCueSegments(3, from: cues),
            translations: ["Hello", nil, nil],
            output: .bilingual,
            targetLanguageCode: "ko"
        )

        // Unchanged text must not be duplicated onto two lines.
        #expect(assembled[0].text == "Hello")
    }
}

extension SubtitleTranslationAssemblerTests {
    /// Engines commonly return a two-speaker cue with a blank line between the lines,
    /// which renders as a gap that pushes the subtitle out of its safe area.
    @Test func collapsesBlankLinesInsideATranslation() {
        #expect(
            SubtitleTranslationAssembler.normalizeLineBreaks("- 그를 믿었나요?\n\n- 그래야만 했어요.")
                == "- 그를 믿었나요?\n- 그래야만 했어요."
        )
        #expect(SubtitleTranslationAssembler.normalizeLineBreaks("한 줄") == "한 줄")
        #expect(
            SubtitleTranslationAssembler.normalizeLineBreaks("  앞줄  \n \n\n  뒷줄 ")
                == "앞줄\n뒷줄"
        )
    }
}

/// A model asked to translate sometimes returns the source unchanged. The length
/// checks pass it — it is exactly the right length — so without an explicit test the
/// run reports success and writes English into a file named `.ko.srt`.
struct SubtitleTranslationEchoTests {
    private let source = "It wasn't that she didn't want to know what it said."

    @Test func rejectsAnExactCopyOfTheSource() {
        #expect(!SubtitleTranslationAssembler.isUsable(translated: source, source: source))
    }

    @Test func rejectsACopyThatDiffersOnlyInSpacingOrFinalPunctuation() {
        #expect(!SubtitleTranslationAssembler.isUsable(
            translated: "  It wasn't that she didn't want to know what it said  ",
            source: source
        ))
    }

    @Test func stillAcceptsARealTranslation() {
        #expect(SubtitleTranslationAssembler.isUsable(
            translated: "그녀가 그 내용을 알고 싶지 않았던 것은 아니었습니다.",
            source: source
        ))
    }

    /// A cue that is just a number comes back unchanged from any honest translator, and
    /// the guard cannot tell that apart from an echo. It counts as untranslated — which
    /// costs nothing, because the fallback is that same text.
    @Test func treatsAnUnchangedNumberAsUntranslated() {
        #expect(!SubtitleTranslationAssembler.isUsable(translated: "1999", source: "1999"))
    }
}

/// The system translator returns CJK punctuation in Korean output — 691 marks in one
/// feature-length film. They are visibly foreign in a Korean subtitle, and equally
/// correct in a Japanese one, so the rule follows the target language.
struct SubtitlePunctuationTests {
    private let cjk = "시작！ 그로부터 12시간 후， 무사히 발견되었습니다。 정말？"

    @Test func rewritesCJKPunctuationForKorean() {
        #expect(
            SubtitleTranslationAssembler.normalizePunctuation(cjk, for: "ko")
                == "시작! 그로부터 12시간 후, 무사히 발견되었습니다. 정말?"
        )
    }

    @Test func leavesJapaneseAlone() {
        #expect(SubtitleTranslationAssembler.normalizePunctuation(cjk, for: "ja") == cjk)
    }

    @Test func leavesChineseAlone() {
        #expect(SubtitleTranslationAssembler.normalizePunctuation(cjk, for: "zh-Hans") == cjk)
    }

    /// An ellipsis and curly quotes are at home in Korean typography; only the wide
    /// forms of marks Korean writes narrow should change.
    @Test func keepsPunctuationKoreanActuallyUses() {
        let text = "그건… “정말”이야"
        #expect(SubtitleTranslationAssembler.normalizePunctuation(text, for: "ko") == text)
    }

    @Test func leavesTextWithNoWidePunctuationUntouched() {
        let text = "Hello, world! Really?"
        #expect(SubtitleTranslationAssembler.normalizePunctuation(text, for: "ko") == text)
    }
}
