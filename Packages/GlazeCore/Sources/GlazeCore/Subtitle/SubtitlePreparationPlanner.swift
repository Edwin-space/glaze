import Foundation

public enum SubtitlePreparationPlan: Equatable, Sendable {
    case useEmbedded(track: EmbeddedSubtitleTrack)
    case translateEmbedded(sourceTrack: EmbeddedSubtitleTrack, targetLanguageCode: String)
    case transcribeAudio(targetLanguageCode: String)

    public var selectedTrack: EmbeddedSubtitleTrack? {
        switch self {
        case .useEmbedded(let track):
            track
        case .translateEmbedded(let sourceTrack, _):
            sourceTrack
        case .transcribeAudio:
            nil
        }
    }
}

/// What is about to be translated.
///
/// This used to be an `EmbeddedSubtitleTrack`, which quietly limited translation to
/// subtitles lifted out of the video container — a subtitle file dropped next to the
/// video, or one Glaze transcribed itself, had no way to describe itself and so could
/// never be translated. Naming the source by what the reader sees, rather than by where
/// it came from, lets all three paths through.
public struct SubtitleTranslationSource: Equatable, Sendable {
    /// Shown in the panel, e.g. an embedded track's title or a subtitle file's name.
    public let displayName: String
    /// nil when the language is unknown; the translator detects it instead.
    public let languageCode: String?

    public init(displayName: String, languageCode: String?) {
        self.displayName = displayName
        self.languageCode = SubtitleLanguageCode.normalized(languageCode)
    }
}

public struct SubtitleTranslationRequest: Equatable, Sendable {
    public let source: SubtitleTranslationSource
    public let targetLanguageCode: String
    public let cues: [SubtitleCue]

    public init(source: SubtitleTranslationSource, targetLanguageCode: String, cues: [SubtitleCue]) {
        self.source = source
        self.targetLanguageCode = targetLanguageCode
        self.cues = cues
    }
}

public enum SubtitlePreparationPlanner {
    public static func plan(
        embeddedTracks: [EmbeddedSubtitleTrack],
        preferredLanguageCodes: [String]
    ) -> SubtitlePreparationPlan {
        let targetLanguage = preferredLanguageCodes
            .compactMap(SubtitleLanguageCode.normalized)
            .first ?? "en"

        if let matchingTrack = preferredTrack(
            from: embeddedTracks.filter { $0.matches(languageCode: targetLanguage) }
        ) {
            return .useEmbedded(track: matchingTrack)
        }

        if let timedTextTrack = preferredTrack(
            from: embeddedTracks.filter(\.canProvideTimedText)
        ) {
            return .translateEmbedded(
                sourceTrack: timedTextTrack,
                targetLanguageCode: targetLanguage
            )
        }

        return .transcribeAudio(targetLanguageCode: targetLanguage)
    }

    private static func preferredTrack(from tracks: [EmbeddedSubtitleTrack]) -> EmbeddedSubtitleTrack? {
        tracks.sorted { lhs, rhs in
            let lhsPriority = priority(for: lhs)
            let rhsPriority = priority(for: rhs)
            return lhsPriority == rhsPriority
                ? lhs.streamIndex < rhs.streamIndex
                : lhsPriority < rhsPriority
        }.first
    }

    private static func priority(for track: EmbeddedSubtitleTrack) -> Int {
        if track.isDefault { return 0 }
        if !track.isForced { return 1 }
        return 2
    }
}
