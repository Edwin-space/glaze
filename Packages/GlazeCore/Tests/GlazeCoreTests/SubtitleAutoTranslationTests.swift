import GlazeCore
import Testing

@Suite("Deciding what to do about a film with no subtitle in the viewer's language")
struct SubtitleAutoTranslationTests {
    @Test("Nothing is offered when there is nothing to translate")
    func silentWithoutATranslatableSubtitle() {
        for setting in SubtitleAutoTranslation.allCases {
            #expect(
                SubtitleAutoTranslationDecision.decide(
                    setting: setting,
                    hasTranslatableSubtitle: false
                ) == .doNothing
            )
        }
    }

    @Test("A standing answer runs without asking again")
    func remembersTheAnswer() {
        #expect(
            SubtitleAutoTranslationDecision.decide(
                setting: .whileWatching,
                hasTranslatableSubtitle: true
            ) == .translate(.whileWatching)
        )
        #expect(
            SubtitleAutoTranslationDecision.decide(
                setting: .beforeWatching,
                hasTranslatableSubtitle: true
            ) == .translate(.beforeWatching)
        )
    }

    @Test("Turning the offer off leaves the film alone")
    func offNeverAsks() {
        #expect(
            SubtitleAutoTranslationDecision.decide(setting: .off, hasTranslatableSubtitle: true)
                == .doNothing
        )
        #expect(
            SubtitleAutoTranslationDecision.decide(setting: .ask, hasTranslatableSubtitle: true)
                == .ask
        )
    }
}

@Suite("Putting a half-finished translation on screen")
struct PartialTranslationAssemblyTests {
    /// What the viewer sees a minute into watching while the engine is still working:
    /// the lines that came back are in Korean, the rest are still the original, and
    /// every line keeps its own timing.
    @Test("Untranslated lines keep their source text")
    func partialRunKeepsSourceForPendingLines() {
        let cues = [
            SubtitleCue(startTime: 0, endTime: 2, text: "Good morning."),
            SubtitleCue(startTime: 2, endTime: 4, text: "The river is frozen.")
        ]
        let segments = SubtitleSegmenter.segments(from: cues)

        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: segments,
            translations: ["좋은 아침입니다."],
            output: .translatedOnly,
            targetLanguageCode: "ko"
        )

        #expect(assembled.count == 2)
        #expect(assembled[0].text == "좋은 아침입니다.")
        #expect(assembled[1].text == "The river is frozen.")
        #expect(assembled[1].startTime == cues[1].startTime)
    }
}
