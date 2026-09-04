import Foundation

/// Why a candidate is where it is in the list.
///
/// Shown next to each result. A viewer choosing between two films with the same name
/// needs to see what the app was going on, not just an order it cannot argue with.
public enum MetadataMatchReason: String, Equatable, Sendable {
    case titleExact
    case titleClose
    case originalTitleMatch
    case yearExact
    case yearNear
    case yearMismatch
    case yearUnknown
    case wellKnown
}

public struct RankedMetadataMatch: Identifiable, Equatable, Sendable {
    public let match: MediaMetadataMatch
    /// 0 to 1. Not a probability — an ordering with a threshold on it.
    public let score: Double
    public let reasons: [MetadataMatchReason]

    public var id: String {
        match.externalIDs.tmdbID ?? "\(match.title)-\(match.year ?? 0)"
    }

    public init(match: MediaMetadataMatch, score: Double, reasons: [MetadataMatchReason]) {
        self.match = match
        self.score = score
        self.reasons = reasons
    }
}

/// Puts the likeliest film first, and says how sure it is.
///
/// A filename is a bad query: `Dune.Part.Two.2024.2160p` searches well, `Avatar` returns
/// six films across thirty years. Rather than guess and write the wrong title beside
/// someone's video — which is worse than writing nothing — this orders the candidates
/// and lets the caller decide whether the top one is clear enough to take without
/// asking.
public enum MetadataMatchRanker {
    /// Above this the top candidate can be taken without asking. Set so that a title
    /// that matches exactly with the right year passes, and little else does.
    public static let confidentThreshold = 0.9

    public static func rank(
        _ matches: [MediaMetadataMatch],
        against parsed: ParsedMediaTitle
    ) -> [RankedMetadataMatch] {
        matches
            .map { score($0, against: parsed) }
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                // A stable order for equals, so the list does not shuffle between runs.
                return (left.match.popularity ?? 0) > (right.match.popularity ?? 0)
            }
    }

    /// Not in doubt on its own terms: the name matches exactly and so does the year.
    static let certainThreshold = 0.95

    /// True when the top candidate can be taken without asking.
    ///
    /// Two ways to earn that. Either it is certain in itself — an exact title with an
    /// exact year is not really a question, even when a similarly named film sits close
    /// behind it — or it is confident and clearly ahead of the runner-up. Everything
    /// else is put to the viewer.
    public static func isUnambiguous(_ ranked: [RankedMetadataMatch]) -> Bool {
        guard let best = ranked.first, best.score >= confidentThreshold else { return false }
        guard ranked.count > 1 else { return true }

        // The shortcut does not apply when the runner-up is exact on both counts too:
        // two films sharing a name and a year is precisely what only a person can tell
        // apart.
        if best.score >= certainThreshold,
           isCertain(best),
           !isCertain(ranked[1]) {
            return true
        }

        return best.score - ranked[1].score >= 0.12
    }

    private static func isCertain(_ candidate: RankedMetadataMatch) -> Bool {
        candidate.reasons.contains(.titleExact) && candidate.reasons.contains(.yearExact)
    }

    private static func score(
        _ match: MediaMetadataMatch,
        against parsed: ParsedMediaTitle
    ) -> RankedMetadataMatch {
        var reasons: [MetadataMatchReason] = []

        // Every name the film goes by is a candidate for what the release group typed.
        let names = [match.title] + [match.originalTitle].compactMap { $0 } + match.matchingTitles
        let titleScore = names.map { similarity(parsed.title, $0) }.max() ?? 0
        if titleScore >= 0.995 {
            reasons.append(.titleExact)
        } else if titleScore >= 0.7 {
            reasons.append(.titleClose)
        }
        let localisedScore = similarity(parsed.title, match.title)
        if titleScore > localisedScore, titleScore >= 0.7 {
            reasons.append(.originalTitleMatch)
        }

        // The year is the strongest signal a filename carries after the title, and the
        // one that separates a remake from the film it remade.
        var yearScore = 0.5
        switch (parsed.year, match.year) {
        case let (parsedYear?, matchYear?) where parsedYear == matchYear:
            yearScore = 1
            reasons.append(.yearExact)
        case let (parsedYear?, matchYear?) where abs(parsedYear - matchYear) <= 1:
            // A film released in December is dated the next year by half the world.
            yearScore = 0.8
            reasons.append(.yearNear)
        case (.some, .some):
            yearScore = 0
            reasons.append(.yearMismatch)
        default:
            reasons.append(.yearUnknown)
        }

        // Never decides a match, only breaks a tie between two that already fit.
        let popularity = match.popularity ?? 0
        let fame = min(popularity / 100, 1)
        if (match.voteCount ?? 0) >= 1_000 {
            reasons.append(.wellKnown)
        }

        let score = titleScore * 0.72 + yearScore * 0.25 + fame * 0.03
        return RankedMetadataMatch(match: match, score: min(score, 1), reasons: reasons)
    }

    /// How alike two titles are, 0 to 1.
    ///
    /// Release names lose punctuation and articles, and Korean libraries routinely hold
    /// `듄 파트2(내장)Dune Part Two` as one filename. So this compares on words as well
    /// as characters and takes the kinder answer: a title fully contained in the other
    /// is a match, not a half-match.
    static func similarity(_ left: String, _ right: String) -> Double {
        let a = normalize(left)
        let b = normalize(right)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }

        let aWords = Set(a.split(separator: " "))
        let bWords = Set(b.split(separator: " "))
        let shared = aWords.intersection(bWords).count
        let containment = Double(shared) / Double(min(aWords.count, bWords.count))
        let overlap = Double(shared) / Double(aWords.union(bWords).count)

        let distance = levenshtein(Array(a), Array(b))
        let characters = 1 - Double(distance) / Double(max(a.count, b.count))

        // Containment carries the case where one title is the other plus extra words,
        // which is what a release name usually is.
        return max(characters, max(overlap, containment * 0.92))
    }

    private static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
