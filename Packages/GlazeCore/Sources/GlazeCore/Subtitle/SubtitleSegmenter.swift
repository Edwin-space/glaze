import Foundation

/// One translation unit: the cues that together carry a single sentence.
///
/// Subtitle cues are display units, not language units — a sentence routinely spans
/// two or three of them. Translating a cue on its own hands the engine a fragment
/// ("Because he did.") with no way to get agreement, tense, or Korean speech level
/// right, so cues are regrouped into sentences before translation and split back
/// afterwards by `SubtitleRedistributor`.
public struct SubtitleSegment: Equatable, Sendable {
    /// Indices into the original cue array, in order.
    public let cueIndices: [Int]
    /// Source text handed to the engine.
    public let text: String

    public init(cueIndices: [Int], text: String) {
        self.cueIndices = cueIndices
        self.text = text
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum SubtitleSegmenter {
    /// Upper bounds so a file with no punctuation at all cannot collapse into one
    /// enormous segment that blows past an engine's input limit.
    public static let maximumCuesPerSegment = 5
    public static let maximumCharactersPerSegment = 400

    /// Marks the end of a sentence. A trailing ellipsis is deliberately absent: in
    /// subtitles it almost always signals the sentence continues into the next cue.
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "。", "！", "？"]
    /// Allowed to trail a sentence ender without cancelling it.
    private static let trailingWrappers: Set<Character> = ["\"", "'", ")", "]", "”", "’", "»", "」", "』"]

    public static func segments(from cues: [SubtitleCue]) -> [SubtitleSegment] {
        var segments: [SubtitleSegment] = []
        var pendingIndices: [Int] = []

        func flush() {
            guard !pendingIndices.isEmpty else { return }
            segments.append(makeSegment(indices: pendingIndices, cues: cues))
            pendingIndices = []
        }

        for index in cues.indices {
            let text = cues[index].text.trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                flush()
                segments.append(SubtitleSegment(cueIndices: [index], text: cues[index].text))
                continue
            }

            // A cue that opens a new speaker or a lyric starts its own sentence.
            if !pendingIndices.isEmpty, startsNewUtterance(text) {
                flush()
            }

            pendingIndices.append(index)

            let reachedLimit = pendingIndices.count >= maximumCuesPerSegment
                || projectedLength(of: pendingIndices, cues: cues) >= maximumCharactersPerSegment

            if endsSentence(text) || isLyric(text) || reachedLimit {
                flush()
            }
        }

        flush()
        return segments
    }

    private static func makeSegment(indices: [Int], cues: [SubtitleCue]) -> SubtitleSegment {
        guard indices.count > 1 else {
            // Single cue: hand the engine exactly what the file contains, newlines and all.
            return SubtitleSegment(cueIndices: indices, text: cues[indices[0]].text)
        }

        // Across cues the newlines are line wrapping, not meaning — rejoin into prose.
        let text = indices
            .map { cues[$0].text.replacingOccurrences(of: "\n", with: " ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")

        return SubtitleSegment(cueIndices: indices, text: text)
    }

    private static func projectedLength(of indices: [Int], cues: [SubtitleCue]) -> Int {
        indices.reduce(0) { $0 + cues[$1].text.count + 1 }
    }

    static func endsSentence(_ text: String) -> Bool {
        var characters = Array(text)
        while let last = characters.last, trailingWrappers.contains(last) {
            characters.removeLast()
        }
        guard let last = characters.last else { return true }

        // An ellipsis is written with the same character as a full stop but means the
        // opposite here: in subtitles it marks a sentence carried into the next cue.
        if last == "…" { return false }
        if last == ".", characters.count >= 2, characters[characters.count - 2] == "." {
            return false
        }

        return sentenceEnders.contains(last)
    }

    /// Dialogue dashes ("- Where is he?") and lyric markers open a fresh utterance
    /// even when the previous cue left a sentence hanging.
    static func startsNewUtterance(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        if first == "-" || first == "–" || first == "—" { return true }
        return isLyric(text)
    }

    static func isLyric(_ text: String) -> Bool {
        text.contains("♪") || text.contains("♫")
    }
}
