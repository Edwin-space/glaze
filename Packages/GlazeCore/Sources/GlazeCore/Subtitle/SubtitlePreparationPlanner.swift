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

public struct SubtitleTranslationRequest: Equatable, Sendable {
    public let sourceTrack: EmbeddedSubtitleTrack
    public let targetLanguageCode: String
    public let cues: [SubtitleCue]

    public init(sourceTrack: EmbeddedSubtitleTrack, targetLanguageCode: String, cues: [SubtitleCue]) {
        self.sourceTrack = sourceTrack
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
