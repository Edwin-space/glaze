import Foundation

/// Splits a translated sentence back across the cues it came from.
///
/// The counterpart to `SubtitleSegmenter`: translation happens per sentence, but
/// display still happens per cue, so the result has to land back on the original
/// timings. Splitting is proportional to how much of the source each cue carried,
/// then nudged to the nearest natural break so no cue ends mid-word.
public enum SubtitleRedistributor {
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]
    private static let clauseBreaks: Set<Character> = [",", ";", ":", "、", "，", "·"]

    /// - Parameters:
    ///   - translated: the sentence as returned by the engine.
    ///   - sourceTexts: the original cue texts the sentence spanned, in order.
    /// - Returns: one string per source cue, in order.
    public static func redistribute(translated: String, across sourceTexts: [String]) -> [String] {
        guard sourceTexts.count > 1 else {
            return [translated.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        let characters = Array(translated.trimmingCharacters(in: .whitespacesAndNewlines))
        guard characters.count >= sourceTexts.count else {
            // Too short to split meaningfully: give it all to the first cue so the
            // text still appears, rather than scattering single characters.
            return [String(characters)] + Array(repeating: "", count: sourceTexts.count - 1)
        }

        // Each cue held roughly this share of the source, so it should hold roughly
        // the same share of the translation.
        let weights = sourceTexts.map { max(1, $0.trimmingCharacters(in: .whitespacesAndNewlines).count) }
        let totalWeight = weights.reduce(0, +)

        var results: [String] = []
        var cursor = 0
        var accumulatedWeight = 0

        for position in sourceTexts.indices {
            if position == sourceTexts.count - 1 {
                results.append(String(characters[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines))
                break
            }

            accumulatedWeight += weights[position]
            let target = Int(
                (Double(accumulatedWeight) / Double(totalWeight) * Double(characters.count)).rounded()
            )
            let remainingCues = sourceTexts.count - position - 1
            // Always leave at least one character for each cue still to come.
            let upperBound = characters.count - remainingCues
            let split = splitIndex(in: characters, near: target, lowerBound: cursor, upperBound: upperBound)

            results.append(String(characters[cursor..<split]).trimmingCharacters(in: .whitespacesAndNewlines))
            cursor = split
        }

        return results
    }

    /// Finds the most natural break near `target`, preferring a sentence end, then a
    /// clause break, then a word boundary. Falls back to the proportional point.
    private static func splitIndex(
        in characters: [Character],
        near target: Int,
        lowerBound: Int,
        upperBound: Int
    ) -> Int {
        guard upperBound > lowerBound + 1 else { return upperBound }

        let clampedTarget = min(max(target, lowerBound + 1), upperBound - 1)
        // Search proportionally to the span so long cues can drift further to find a break.
        let window = max(8, (upperBound - lowerBound) / 3)
        let low = max(lowerBound + 1, clampedTarget - window)
        let high = min(upperBound - 1, clampedTarget + window)
        guard low <= high else { return clampedTarget }

        var best: (index: Int, score: Int, distance: Int)?

        for index in low...high {
            let previous = characters[index - 1]
            let score: Int
            if sentenceEnders.contains(previous) {
                score = 3
            } else if clauseBreaks.contains(previous) {
                score = 2
            } else if previous.isWhitespace || characters[index].isWhitespace {
                score = 1
            } else {
                continue
            }

            let distance = abs(index - clampedTarget)
            if let current = best {
                let isBetter = score > current.score
                    || (score == current.score && distance < current.distance)
                if isBetter { best = (index, score, distance) }
            } else {
                best = (index, score, distance)
            }
        }

        return best?.index ?? clampedTarget
    }
}
