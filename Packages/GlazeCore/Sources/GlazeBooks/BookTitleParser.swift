import Foundation
import GlazeCore

public struct ParsedBookTitle: Equatable, Sendable {
    public let title: String
    public let volume: Int?
    /// The word the name used for the number — `권`, `화`, `집`, `巻`. Nil when the
    /// number came from `Vol.`, `#`, or a bare digit, where the display falls back to
    /// the localised form.
    public let unit: String?

    public init(title: String, volume: Int?, unit: String? = nil) {
        self.title = title
        self.volume = volume
        self.unit = unit
    }
}

/// Pulls the volume number out of a comic's file name so twenty files become one row.
///
/// A folder of manga is `원피스 01권.cbz` through `원피스 24권.cbz`. Shown as they are,
/// that is twenty-four covers of the same book. The number is what turns them into
/// one shelf entry, so finding it reliably is the whole job.
public enum BookTitleParser {
    public static func parse(fileName: String, kind: BookItem.Kind) -> ParsedBookTitle {
        // A Mac's filesystem hands back Hangul decomposed, so the `권` in a file name
        // arrives as three code points and does not match the one written here. Every
        // Korean comic on the shelf would keep its volume number in its title.
        let normalized = fileName.precomposedStringWithCanonicalMapping
        let stem = (normalized as NSString).deletingPathExtension
        let cleaned = strippingBrackets(from: stem)
        guard !cleaned.isEmpty else { return ParsedBookTitle(title: stem, volume: nil) }


        guard let marker = lastMarker(in: cleaned, kind: kind) else {
            return ParsedBookTitle(title: cleaned, volume: nil)
        }

        let title = trimSeparators(String(cleaned.prefix(marker.start)))
        // `01권.cbz` on its own has a number and nothing else. The number is still the
        // volume, but the folder has to name the book, so the caller's fallback wins.
        guard !title.isEmpty else {
            return ParsedBookTitle(title: cleaned, volume: marker.volume, unit: marker.unit)
        }
        return ParsedBookTitle(title: title, volume: marker.volume, unit: marker.unit)
    }

    // MARK: - Markers

    private struct Marker {
        let start: Int
        let volume: Int
        let unit: String?
    }

    /// The last marker wins: `배트맨 v2 03권` is volume 3 of a second run, not volume 2.
    private static func lastMarker(in text: String, kind: BookItem.Kind) -> Marker? {
        // A written-out marker beats a bare number wherever both appear. `One Piece
        // Volume 12` has both, and reading the bare `12` there leaves the word
        // "Volume" stranded on the end of the title.
        let explicit = explicitPatterns
            .compactMap { match(pattern: $0.pattern, in: text, unitGroup: $0.unitGroup) }
            .max { $0.start < $1.start }
        if let explicit { return explicit }
        // A bare trailing number is only trustworthy on a comic. PDFs carry years and
        // edition numbers in their names — `Blade Runner 2049.pdf` is not volume 2049,
        // and `C Programming 2nd.pdf` is not volume 2.
        guard kind == .comic else { return nil }
        return match(pattern: barePattern, in: text, unitGroup: nil)
    }

    /// Written out rather than assembled so each line is readable on its own.
    /// `unitGroup` names the capture holding the word the file used for the number,
    /// where there is one.
    private static let explicitPatterns: [(pattern: String, unitGroup: Int?)] = [
        // `Vol. 3`, `Volume 12`, `v03` — the separator before it stops `Chevy 5` matching.
        (#"(?:^|[\s\-_.\[(])(?:volume|vol|v)\.?\s*(\d{1,4})(?![\d])"#, nil),
        // `3권`, `12화`, `5집`, `3巻`
        (#"(\d{1,4})\s*(권|화|집|巻)"#, 2),
        // `Berserk #14`
        (#"#\s*(\d{1,4})"#, nil)
    ]

    private static let barePattern = #"[\s\-_.]+(\d{1,3})\s*$"#

    private static func match(pattern: String, in text: String, unitGroup: Int?) -> Marker? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let found = regex.matches(in: text, range: range).last,
              let numberRange = Range(found.range(at: 1), in: text),
              let volume = Int(text[numberRange]), volume > 0,
              let wholeRange = Range(found.range, in: text)
        else { return nil }

        var unit: String?
        if let unitGroup, found.numberOfRanges > unitGroup,
           let unitRange = Range(found.range(at: unitGroup), in: text) {
            unit = String(text[unitRange])
        }

        return Marker(
            start: text.distance(from: text.startIndex, to: wholeRange.lowerBound),
            volume: volume,
            unit: unit
        )
    }

    // MARK: - Tidying

    /// Scan groups, release tags and volume ranges travel with comics:
    /// `[스캔] 슬램덩크 07 (완전판)`, `원피스 1~24권 완결`.
    ///
    /// The range matters because one archive routinely holds a whole run and is named
    /// for it. Left in, `원피스 1~24권` parses as volume 24 of a book called
    /// `원피스 1~`, and every volume inside inherits that name.
    private static func strippingBrackets(from text: String) -> String {
        var result = text
        let patterns = [
            #"^\s*\[[^\]]*\]"#,
            #"\([^)]*\)\s*$"#,
            #"\[[^\]]*\]\s*$"#,
            // `1~24권`, `01-21화`, `Vol.1-9`
            #"(?i)(?:vol\.?\s*)?\d{1,4}\s*[~\-–—]\s*\d{1,4}\s*(?:권|화|집|巻)?"#,
            #"\s*(?:완결|합본|전권)\s*$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..<result.endIndex, in: result),
                withTemplate: ""
            )
        }
        return trimSeparators(result)
    }

    private static func trimSeparators(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " \t-_.·,"))
    }
}
