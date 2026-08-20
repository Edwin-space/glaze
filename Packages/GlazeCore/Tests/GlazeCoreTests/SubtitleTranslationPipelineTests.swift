import Testing
@testable import GlazeCore

/// End-to-end checks over the segment → translate → reassemble path, on subtitle
/// shapes that actually occur: a sentence split across cues, a two-speaker exchange,
/// a lyric, and a sentence broken by an ellipsis.
struct SubtitleTranslationPipelineTests {
    private let cues = [
        SubtitleCue(startTime: 0, endTime: 2, text: "I didn't leave the silo"),
        SubtitleCue(startTime: 2, endTime: 4, text: "because he asked me to stay."),
        SubtitleCue(startTime: 4, endTime: 6, text: "- Did you believe him?\n- I had to."),
        SubtitleCue(startTime: 6, endTime: 8, text: "♪ the world outside ♪"),
        SubtitleCue(startTime: 8, endTime: 10, text: "Every day it gets"),
        SubtitleCue(startTime: 10, endTime: 12, text: "harder to see..."),
        SubtitleCue(startTime: 12, endTime: 14, text: "what they hid from us.")
    ]

    /// The whole point of segmenting: fewer, complete sentences reach the engine.
    @Test func groupsSplitSentencesButKeepsUtterancesApart() {
        let segments = SubtitleSegmenter.segments(from: cues)

        #expect(segments.count == 4)
        #expect(segments[0].cueIndices == [0, 1])
        #expect(segments[0].text == "I didn't leave the silo because he asked me to stay.")
        #expect(segments[1].cueIndices == [2])
        #expect(segments[2].cueIndices == [3])
        // The ellipsis carries the sentence through all three closing cues.
        #expect(segments[3].cueIndices == [4, 5, 6])
    }

    /// Reassembly must return exactly the original cue list shape and timings, no
    /// matter how the sentences were grouped.
    @Test func reassemblyPreservesCueCountAndTimings() {
        let segments = SubtitleSegmenter.segments(from: cues)
        let translations: [String?] = [
            "그가 남아달라고 부탁했기 때문에 나는 사일로를 떠나지 않았어요.",
            "- 그를 믿었나요? - 그래야만 했어요.",
            nil,
            "그들이 우리에게 숨긴 것을 보는 게 날마다 점점 더 어려워져요."
        ]

        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: segments,
            translations: translations,
            output: .translatedOnly
        )

        #expect(assembled.count == cues.count)
        for index in cues.indices {
            #expect(assembled[index].startTime == cues[index].startTime)
            #expect(assembled[index].endTime == cues[index].endTime)
        }
    }

    /// A segment the engine declined leaves its cues untouched while its neighbours
    /// still get translated.
    @Test func skippedSegmentDoesNotAffectItsNeighbours() {
        let segments = SubtitleSegmenter.segments(from: cues)
        let translations: [String?] = [
            "그가 남아달라고 부탁했기 때문에 나는 사일로를 떠나지 않았어요.",
            nil,
            nil,
            "그들이 우리에게 숨긴 것을 보는 게 날마다 점점 더 어려워져요."
        ]

        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: segments,
            translations: translations,
            output: .translatedOnly
        )

        #expect(assembled[2].text == cues[2].text)
        #expect(assembled[3].text == cues[3].text)
        #expect(assembled[0].text != cues[0].text)
        #expect(assembled[6].text != cues[6].text)
    }

    @Test func bilingualKeepsEverySourceLine() {
        let segments = SubtitleSegmenter.segments(from: cues)
        let translations: [String?] = [
            "그가 남아달라고 부탁했기 때문에 나는 사일로를 떠나지 않았어요.",
            nil,
            nil,
            "그들이 우리에게 숨긴 것을 보는 게 날마다 점점 더 어려워져요."
        ]

        let assembled = SubtitleTranslationAssembler.assemble(
            cues: cues,
            segments: segments,
            translations: translations,
            output: .bilingual
        )

        for index in cues.indices {
            #expect(assembled[index].text.hasPrefix(cues[index].text))
        }
    }
}
