import Foundation

/// What a film is, read out of the name a release group gave it.
///
/// A NAS lists files, not titles: `Avatar.Fire.and.Ash.2025.2160p.HDR10Plus.DV.WEBRip.
/// 6CH.x265.HEVC-PSA`. On a Mac that is tolerable because the viewer is reading a file
/// browser. On a television three metres away it is unreadable, and there are no
/// posters coming from DLNA to carry the shelf instead — the title has to do that work
/// on its own.
///
/// Everything after the year is release metadata, which is the seam this splits on.
public struct ParsedMediaTitle: Equatable, Sendable {
    /// What to show large.
    public let title: String
    public let year: Int?
    /// Set for series episodes, e.g. `S01E01`.
    public let season: Int?
    public let episode: Int?
    /// The episode's own name, when the release carried one:
    /// `Fallout.S01E01.The.End.2160p…` is called "The End". An episode list that fell
    /// back to the whole release string was unreadable across a room.
    public let episodeTitle: String?
    /// Short marks worth showing next to the title — resolution, dynamic range, audio.
    public let badges: [String]

    public init(
        title: String,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil,
        badges: [String] = []
    ) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
        self.badges = badges
    }
}

public enum MediaTitleParser {
    public static func parse(_ raw: String) -> ParsedMediaTitle {
        let cleaned = stripSitePrefix(raw)
        let badges = badges(in: cleaned)
        let (season, episode) = episodeNumbers(in: cleaned)

        var working = cleaned
        // Bracketed groups are always metadata: [2160p] [4K] [WEB] [YTS.MX].
        working = working.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)

        let year = year(in: working)
        working = truncate(working, atYear: year, season: season)
        working = separatorsToSpaces(working)

        let title = working
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            // Includes the opening bracket a parenthesised year leaves behind.
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—,._([{"))

        return ParsedMediaTitle(
            title: title.isEmpty ? raw : title,
            year: year,
            season: season,
            episode: episode,
            episodeTitle: season == nil ? nil : episodeTitle(in: cleaned),
            badges: badges
        )
    }

    /// `PSArips.com | Avatar…` — the site that packaged it is not part of the title.
    private static func stripSitePrefix(_ raw: String) -> String {
        guard let separator = raw.range(of: " | ") else { return raw }
        return String(raw[separator.upperBound...])
    }

    private static func year(in text: String) -> Int? {
        // Anchored on a separator so a year inside a title like "2012" survives only
        // when it really is the release year sitting between metadata.
        let pattern = #"(?:^|[\s.\(\[])((?:19|20)\d{2})(?:[\s.\)\]]|$)"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = text[match].filter(\.isNumber)
        return Int(digits)
    }

    private static func episodeNumbers(in text: String) -> (Int?, Int?) {
        let pattern = #"[Ss](\d{1,2})(?:[Ee](\d{1,3}))?"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return (nil, nil) }
        let token = String(text[range])
        let numbers = token
            .dropFirst()
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        return (numbers.first, numbers.count > 1 ? numbers[1] : nil)
    }

    /// What sits between `S01E01` and the first piece of release metadata.
    ///
    /// The metadata always starts with a resolution, a source or a year, so the name
    /// runs from the episode marker up to whichever of those appears first. A release
    /// that names no episode leaves nothing between the two, which is the same answer
    /// as not knowing.
    private static func episodeTitle(in text: String) -> String? {
        let markerPattern = #"[Ss]\d{1,2}[Ee]\d{1,3}"#
        guard let marker = text.range(of: markerPattern, options: .regularExpression) else {
            return nil
        }

        let remainder = text[marker.upperBound...]
        let yearOrMetadata = #"(?i)[\s._\-](19|20)\d{2}\b"#
        let end = min(
            remainder.range(of: releaseMetadataPattern, options: .regularExpression)?.lowerBound
                ?? remainder.endIndex,
            remainder.range(of: yearOrMetadata, options: .regularExpression)?.lowerBound
                ?? remainder.endIndex
        )

        let name = separatorsToSpaces(String(remainder[remainder.startIndex..<end]))
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—,._"))

        return name.isEmpty ? nil : name
    }

    /// Cuts at whichever marker comes first — the year, the season, or failing both,
    /// the first piece of release metadata.
    ///
    /// That last case is not a nicety. Plenty of releases carry no year at all
    /// (`Nosferatu.1080p.WEB-DL.x265-GROUP`), and without a cut the "title" became the
    /// whole filename, which no metadata service can find anything for.
    private static func truncate(_ text: String, atYear year: Int?, season: Int?) -> String {
        var cutIndex: String.Index?

        if let year, let range = text.range(of: String(year)) {
            cutIndex = range.lowerBound
        }

        if season != nil,
           let range = text.range(of: #"[\s.][Ss]\d{1,2}(?:[Ee]\d{1,3})?"#, options: .regularExpression) {
            cutIndex = min(cutIndex ?? range.lowerBound, range.lowerBound)
        }

        if cutIndex == nil,
           let range = text.range(of: releaseMetadataPattern, options: .regularExpression) {
            cutIndex = range.lowerBound
        }

        guard let cutIndex else { return text }
        return String(text[text.startIndex..<cutIndex])
    }

    /// Where a release name stops describing the film and starts describing the file.
    static let releaseMetadataPattern =
        #"(?i)[\s._\-](2160p|1080p|720p|480p|4K|UHD|WEB[\s._-]?DL|WEBRip|BluRay|BDRip|BRRip|HDTV|DVDRip|REMUX|HDR10\+?|HDR|Dolby[\s._-]?Vision|AMZN|NF|DSNP|HMAX|ATVP|x26[45]|H[\s._-]?26[45]|HEVC|AVC|DDP?[0-9]|DTS|AAC|AC3|Atmos|TrueHD|MULTi|KORSUB|IMAX)\b"#

    /// Dots and underscores stand in for spaces in release names, but a dot between
    /// single letters is an abbreviation and stays.
    private static func separatorsToSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"(?<=[^\s])\.(?=[^\s])"#, with: " ", options: .regularExpression)
    }

    private static let badgeRules: [(pattern: String, badge: String)] = [
        (#"(?i)(2160p|\b4K\b|UHD)"#, "4K"),
        (#"(?i)1080p"#, "1080p"),
        (#"(?i)720p"#, "720p"),
        (#"(?i)(HDR10Plus|HDR10\+)"#, "HDR10+"),
        (#"(?i)HDR"#, "HDR"),
        (#"(?i)(\bDV\b|Dolby.?Vision)"#, "Dolby Vision"),
        (#"(?i)Atmos"#, "Atmos"),
        (#"(?i)REMUX"#, "REMUX")
    ]

    private static func badges(in text: String) -> [String] {
        var found: [String] = []
        for rule in badgeRules where text.range(of: rule.pattern, options: .regularExpression) != nil {
            // HDR10+ already says HDR; one mark is enough on a shelf.
            if rule.badge == "HDR", found.contains("HDR10+") { continue }
            if found.contains(rule.badge) { continue }
            found.append(rule.badge)
        }
        // Only one resolution can be true.
        if found.contains("4K") {
            found.removeAll { $0 == "1080p" || $0 == "720p" }
        }
        return found
    }
}
