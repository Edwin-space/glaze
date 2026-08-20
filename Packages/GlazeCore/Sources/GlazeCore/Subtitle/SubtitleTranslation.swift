import Foundation

/// Platform-independent half of subtitle translation.
///
/// The engine itself is supplied per platform (macOS drives Apple's on-device
/// Translation framework), but the output shaping lives here so iOS and tvOS reuse
/// identical behaviour — the same reason `SubtitlePreparationPlanner` sits in Core.
public enum SubtitleTranslationOutput: String, Equatable, Sendable, CaseIterable {
    /// Replace the source line with the translation.
    case translatedOnly
    /// Source line on top, translation underneath — the language-learning mode the
    /// product direction calls for ("원문 + 한국어").
    case bilingual

    public var labelKey: String {
        switch self {
        case .translatedOnly: "subtitle.translate.output.translated_only"
        case .bilingual: "subtitle.translate.output.bilingual"
        }
    }
}

public enum SubtitleTranslationError: Error, Equatable, Sendable {
    /// The pair is not supported, or its on-device assets are not installed.
    case languagePairUnavailable
    /// The engine returned, but produced nothing usable.
    case translationFailed
}

/// Reassembles translated text onto the original cues.
public enum SubtitleTranslationAssembler {
    /// Merges translated text back onto the original cues, preserving timings.
    ///
    /// Results are keyed by cue index rather than zipped positionally: the engine can
    /// skip a line it cannot translate, and zipping would then shift every later
    /// translation onto the wrong timestamp. A cue with no usable translation keeps
    /// its source text rather than going blank.
    public static func merge(
        cues: [SubtitleCue],
        translations: [Int: String],
        output: SubtitleTranslationOutput
    ) -> [SubtitleCue] {
        cues.enumerated().map { index, cue in
            guard let translated = translations[index]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translated.isEmpty,
                  translated != cue.text else {
                return cue
            }

            let text = switch output {
            case .translatedOnly: translated
            case .bilingual: "\(cue.text)\n\(translated)"
            }

            return SubtitleCue(startTime: cue.startTime, endTime: cue.endTime, text: text)
        }
    }
}
