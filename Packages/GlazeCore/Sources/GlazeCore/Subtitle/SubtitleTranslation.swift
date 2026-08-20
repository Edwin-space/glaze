import Foundation

/// Platform-independent half of subtitle translation.
///
/// The engine is supplied per platform (macOS drives Apple's on-device Translation
/// framework today; a Foundation Models engine and a user-supplied endpoint are the
/// planned additions), while segmentation, redistribution, validation, and output
/// shaping live here so every platform behaves identically.
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

/// Identifies which engine produced a translation. Engines are added over time —
/// the system translator ships first, with an on-device LLM and a user-supplied
/// endpoint planned — so the rest of the app refers to them through this.
public enum SubtitleTranslationEngineID: String, Equatable, Sendable, CaseIterable {
    /// Apple's system translation. No setup, widest language coverage, but no way
    /// to steer context or Korean speech level.
    case appleTranslation
    /// Apple's on-device language model. Can be told about surrounding dialogue and
    /// tone, at the cost of requiring Apple Intelligence.
    case appleFoundationModel
    /// An OpenAI-compatible endpoint the user runs themselves (Ollama, LM Studio, …).
    /// Glaze never ships or fetches model weights; it only talks to what is already there.
    case externalEndpoint

    public var labelKey: String {
        switch self {
        case .appleTranslation: "subtitle.translate.engine.system"
        case .appleFoundationModel: "subtitle.translate.engine.on_device_ai"
        case .externalEndpoint: "subtitle.translate.engine.external"
        }
    }
}

/// A translation backend.
///
/// `@MainActor` because the first implementation wraps `TranslationSession`, a
/// non-Sendable class SwiftUI vends on the main actor. Implementations that do their
/// own I/O (a local HTTP endpoint, for instance) still suspend on `await`, so this
/// does not block the UI.
@MainActor
public protocol SubtitleTranslationEngine {
    var engineID: SubtitleTranslationEngineID { get }

    /// Translates whole segments, reporting fractional progress as it goes.
    /// - Returns: one translation per segment, in the same order. An entry may be
    ///   `nil` when that segment could not be translated; the caller keeps the source.
    func translate(
        segments: [SubtitleSegment],
        targetLanguageCode: String,
        onProgress: (Double) -> Void
    ) async throws -> [String?]
}

/// Turns engine output back into cues.
public enum SubtitleTranslationAssembler {
    /// A translation this far from the source length is almost always the engine
    /// having rambled or echoed its prompt rather than translated.
    static let minimumLengthRatio = 0.15
    static let maximumLengthRatio = 6.0

    /// Rebuilds the cue list from per-segment translations.
    ///
    /// Anything that fails validation falls back to the source text for those cues,
    /// so a bad line degrades to the original rather than to a blank subtitle.
    public static func assemble(
        cues: [SubtitleCue],
        segments: [SubtitleSegment],
        translations: [String?],
        output: SubtitleTranslationOutput
    ) -> [SubtitleCue] {
        var translatedByCueIndex: [Int: String] = [:]

        for (position, segment) in segments.enumerated() {
            guard position < translations.count,
                  let translated = translations[position],
                  isUsable(translated: translated, source: segment.text) else {
                continue
            }

            let sourceTexts = segment.cueIndices.map { cues[$0].text }
            let pieces = SubtitleRedistributor.redistribute(translated: translated, across: sourceTexts)

            for (offset, cueIndex) in segment.cueIndices.enumerated() where offset < pieces.count {
                translatedByCueIndex[cueIndex] = pieces[offset]
            }
        }

        return cues.enumerated().map { index, cue in
            guard let translated = translatedByCueIndex[index]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
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

    static func isUsable(translated: String, source: String) -> Bool {
        let trimmedTranslation = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTranslation.isEmpty else { return false }
        guard !trimmedSource.isEmpty else { return false }

        let ratio = Double(trimmedTranslation.count) / Double(trimmedSource.count)
        return ratio >= minimumLengthRatio && ratio <= maximumLengthRatio
    }
}
