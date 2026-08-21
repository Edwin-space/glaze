import Foundation

public struct SubtitleFile: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable {
        case original
        case korean
        case unknown
    }

    public let id = UUID()
    public let url: URL
    public let kind: Kind

    public var displayName: String {
        url.lastPathComponent
    }

    /// The language the file names itself with — `Movie.en.srt` reads as `en`.
    ///
    /// nil when the name carries no recognizable tag, in which case the translator is
    /// left to detect the language from the text instead of trusting a guess.
    public var languageCode: String? {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: ".")
        guard parts.count >= 2, let tag = parts.last else { return nil }
        guard let normalized = SubtitleLanguageCode.normalized(String(tag)) else { return nil }
        // Without this, any trailing word passes — `Movie.final.srt` would claim to be
        // the language "final".
        guard Locale.LanguageCode(normalized).isISOLanguage else { return nil }
        return normalized
    }

    public static func manual(url: URL) -> SubtitleFile {
        SubtitleFile(url: url, kind: kind(for: url))
    }

    private static func kind(for url: URL) -> Kind {
        let lowercasedName = url.deletingPathExtension().lastPathComponent.lowercased()

        if lowercasedName.hasSuffix(".ko") || lowercasedName.hasSuffix(".kor") || lowercasedName.hasSuffix(".kr") {
            return .korean
        }

        if lowercasedName.hasSuffix(".original") || lowercasedName.hasSuffix(".en") || lowercasedName.hasSuffix(".eng") {
            return .original
        }

        return .unknown
    }
}
