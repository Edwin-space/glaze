import Foundation

public struct EmbeddedSubtitleTrack: Identifiable, Equatable, Hashable, Sendable {
    public enum ContentKind: String, Equatable, Hashable, Sendable {
        case timedText
        case bitmap
        case unknown
    }

    public let streamIndex: Int
    public let codec: String
    public let languageCode: String?
    public let title: String?
    public let isDefault: Bool
    public let isForced: Bool
    public let contentKind: ContentKind

    public init(
        streamIndex: Int,
        codec: String,
        languageCode: String? = nil,
        title: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        contentKind: ContentKind? = nil
    ) {
        self.streamIndex = streamIndex
        self.codec = codec
        self.languageCode = SubtitleLanguageCode.normalized(languageCode)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.isDefault = isDefault
        self.isForced = isForced
        self.contentKind = contentKind ?? Self.contentKind(for: codec)
    }

    public var id: String {
        "embedded:\(streamIndex)"
    }

    public var canProvideTimedText: Bool {
        contentKind == .timedText
    }

    public func matches(languageCode: String) -> Bool {
        guard let trackLanguage = SubtitleLanguageCode.normalized(self.languageCode),
              let requestedLanguage = SubtitleLanguageCode.normalized(languageCode) else {
            return false
        }

        return trackLanguage == requestedLanguage
    }

    private static func contentKind(for codec: String) -> ContentKind {
        switch codec.lowercased() {
        case "ass", "ssa", "mov_text", "srt", "subrip", "text", "ttml", "webvtt":
            .timedText
        case "dvb_subtitle", "dvd_subtitle", "hdmv_pgs_subtitle", "pgssub", "xsub":
            .bitmap
        default:
            .unknown
        }
    }
}

public enum SubtitleLanguageCode {
    public static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let baseCode = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first?
            .lowercased()

        guard let baseCode, !baseCode.isEmpty, baseCode != "und" else {
            return nil
        }

        return iso639Aliases[baseCode] ?? baseCode
    }

    private static let iso639Aliases: [String: String] = [
        "chi": "zh", "zho": "zh",
        "deu": "de", "ger": "de",
        "eng": "en",
        "fra": "fr", "fre": "fr",
        "ita": "it",
        "jpn": "ja",
        "kor": "ko",
        "por": "pt",
        "rus": "ru",
        "spa": "es",
        "tha": "th",
        "vie": "vi"
    ]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
