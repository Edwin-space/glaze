import Testing
@testable import GlazeCore

struct SubtitleRedistributorTests {
    @Test func singleCueKeepsWholeTranslation() {
        let pieces = SubtitleRedistributor.redistribute(
            translated: "그가 부탁해서 남았어요.",
            across: ["I stayed because he asked."]
        )

        #expect(pieces == ["그가 부탁해서 남았어요."])
    }

    /// Nothing may be lost or duplicated when the sentence is split back apart.
    @Test func splitPiecesReconstructTheTranslation() {
        let translated = "그가 부탁했기 때문에 나는 떠나지 않았어요."
        let pieces = SubtitleRedistributor.redistribute(
            translated: translated,
            across: ["I didn't leave", "because he asked me to."]
        )

        #expect(pieces.count == 2)
        let rejoined = pieces.joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
        #expect(rejoined == translated)
    }

    @Test func neverSplitsInsideAWord() {
        let pieces = SubtitleRedistributor.redistribute(
            translated: "The quick brown fox jumps over the lazy dog today",
            across: ["The quick brown fox", "jumps over the lazy dog today"]
        )

        for piece in pieces {
            #expect(!piece.isEmpty)
            #expect(piece == piece.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Both halves are whole words, so every token survives intact.
        let tokens = pieces.joined(separator: " ").split(separator: " ").map(String.init)
        #expect(tokens.count == 10)
    }

    @Test func producesOnePieceForEachSourceCue() {
        let pieces = SubtitleRedistributor.redistribute(
            translated: "하나 둘 셋 넷 다섯 여섯 일곱 여덟",
            across: ["one two", "three four", "five six", "seven eight"]
        )

        #expect(pieces.count == 4)
        #expect(pieces.allSatisfy { !$0.isEmpty })
    }

    /// A translation shorter than the cue count cannot be split sensibly; it goes to
    /// the first cue rather than being cut into single characters.
    @Test func handlesTranslationShorterThanCueCount() {
        let pieces = SubtitleRedistributor.redistribute(
            translated: "네",
            across: ["Yes", "indeed", "sir", "of course"]
        )

        #expect(pieces.count == 4)
        #expect(pieces[0] == "네")
        #expect(Array(pieces.dropFirst()) == ["", "", ""])
    }

    @Test func prefersBreakingAtClausePunctuation() {
        let pieces = SubtitleRedistributor.redistribute(
            translated: "그는 떠났고, 그녀는 남았다",
            across: ["He left,", "she stayed"]
        )

        #expect(pieces[0].hasSuffix(","))
    }
}
