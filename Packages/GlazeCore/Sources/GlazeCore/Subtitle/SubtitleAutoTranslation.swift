import Foundation

/// What to do when a film opens with subtitles, but none in the language the viewer
/// reads — and one of the tracks it does carry could be translated.
///
/// The choice is worth making explicit rather than deciding for people. Translating a
/// two-hour film takes minutes, so starting it silently would either delay the film or
/// churn away unasked; never offering it leaves the feature buried in a panel nobody
/// opens. Asking once, and remembering the answer, is the middle.
public enum SubtitleAutoTranslation: String, CaseIterable, Codable, Sendable {
    /// Ask each time a film opens with nothing in the viewer's language.
    case ask
    /// Start playing at once and swap each line in as it is translated.
    case whileWatching
    /// Translate the whole film first, then play.
    case beforeWatching
    /// Never offer. The subtitle panel's own button still works.
    case off

    public static let `default` = SubtitleAutoTranslation.ask

    public var labelKey: String { "subtitle.auto_translate.\(rawValue)" }
}

/// Whether a film that has just opened should lead to a translation, and how.
public enum SubtitleAutoTranslationDecision: Equatable, Sendable {
    case ask
    case translate(SubtitleTranslationTiming)
    case doNothing

    public static func decide(
        setting: SubtitleAutoTranslation,
        hasTranslatableSubtitle: Bool
    ) -> SubtitleAutoTranslationDecision {
        guard hasTranslatableSubtitle else { return .doNothing }
        return switch setting {
        case .ask: .ask
        case .whileWatching: .translate(.whileWatching)
        case .beforeWatching: .translate(.beforeWatching)
        case .off: .doNothing
        }
    }
}

/// When the viewer watches relative to the translation running.
public enum SubtitleTranslationTiming: String, Equatable, Sendable, CaseIterable {
    /// The film plays; lines are replaced as they come back from the engine.
    case whileWatching
    /// The film waits until every line is translated.
    case beforeWatching
}
