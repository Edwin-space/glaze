import Testing
@testable import GlazeCore

struct SubtitleSegmenterTests {
    private func cue(_ text: String, _ start: Double) -> SubtitleCue {
        SubtitleCue(startTime: start, endTime: start + 1, text: text)
    }

    /// The core case: one sentence split across cues must reach the engine whole.
    @Test func joinsCuesThatContinueASentence() {
        let cues = [
            cue("I didn't leave", 0),
            cue("because he asked me to.", 1)
        ]

        let segments = SubtitleSegmenter.segments(from: cues)

        #expect(segments.count == 1)
        #expect(segments[0].cueIndices == [0, 1])
        #expect(segments[0].text == "I didn't leave because he asked me to.")
    }

    @Test func keepsCompleteSentencesSeparate() {
        let cues = [cue("Hello.", 0), cue("How are you?", 1)]

        let segments = SubtitleSegmenter.segments(from: cues)

        #expect(segments.count == 2)
        #expect(segments.map(\.cueIndices) == [[0], [1]])
    }

    /// A hanging sentence must not swallow the next speaker's line.
    @Test func dialogueDashStartsANewSegment() {
        let cues = [
            cue("I was going to say", 0),
            cue("- Don't.", 1)
        ]

        let segments = SubtitleSegmenter.segments(from: cues)

        #expect(segments.count == 2)
        #expect(segments[1].cueIndices == [1])
    }

    @Test func lyricsStandAlone() {
        let cues = [
            cue("He walks away", 0),
            cue("♪ and the music plays ♪", 1),
            cue("into the night.", 2)
        ]

        let segments = SubtitleSegmenter.segments(from: cues)

        #expect(segments.map(\.cueIndices) == [[0], [1], [2]])
    }

    /// Trailing ellipsis signals continuation in subtitles, not a finished sentence.
    @Test func treatsTrailingEllipsisAsContinuation() {
        let cues = [cue("If you had told me...", 0), cue("things would be different.", 1)]

        let segments = SubtitleSegmenter.segments(from: cues)

        #expect(segments.count == 1)
    }

    @Test func closingQuoteDoesNotCancelSentenceEnd() {
        #expect(SubtitleSegmenter.endsSentence("\"Get out.\""))
        #expect(SubtitleSegmenter.endsSentence("(He left.)"))
        #expect(!SubtitleSegmenter.endsSentence("and then"))
    }

    /// A file with no punctuation must not collapse into one unbounded segment.
    @Test func capsSegmentLength() {
        let cues = (0..<12).map { cue("line \($0)", Double($0)) }

        let segments = SubtitleSegmenter.segments(from: cues)

        #expect(segments.allSatisfy { $0.cueIndices.count <= SubtitleSegmenter.maximumCuesPerSegment })
        #expect(segments.flatMap(\.cueIndices) == Array(0..<12))
    }

    /// Every cue must appear exactly once, in order — a dropped index would shift
    /// the whole file's timing on reassembly.
    @Test func coversEveryCueExactlyOnceInOrder() {
        let cues = [
            cue("First part", 0),
            cue("of a sentence.", 1),
            cue("- A reply.", 2),
            cue("", 3),
            cue("Trailing fragment", 4)
        ]

        let segments = SubtitleSegmenter.segments(from: cues)

        #expect(segments.flatMap(\.cueIndices) == [0, 1, 2, 3, 4])
    }
}
