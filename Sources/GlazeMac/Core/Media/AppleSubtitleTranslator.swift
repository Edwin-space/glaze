import Foundation
import GlazeCore
// TranslationSession is a non-Sendable class that has not been audited for Swift 6
// concurrency. Every call on it below stays on the main actor, which is where SwiftUI
// vends the session in the first place.
@preconcurrency import Translation

/// Drives Apple's on-device Translation framework over a set of subtitle cues.
///
/// The session is not created here: `TranslationSession` is only vended by SwiftUI's
/// `.translationTask` modifier, so the view hands one in and this type does the work.
/// Keeping it session-agnostic also means the same path serves any screen that starts
/// a translation.
enum AppleSubtitleTranslator {
    /// Translates `cues`, reporting fractional progress as it goes.
    ///
    /// Cues are translated one at a time rather than through `translations(from:)`.
    /// The batch API takes and returns non-Sendable types, which cannot cross out of
    /// the main actor the session lives on; a plain `String` in and a `Sendable`
    /// response back can. Translation is on-device and fast relative to transcription,
    /// so the extra round trips are not the bottleneck — and progress moves per line.
    ///
    /// - Returns: cues in the original order, with timings untouched.
    @MainActor
    static func translate(
        cues: [SubtitleCue],
        output: SubtitleTranslationOutput,
        using session: TranslationSession,
        onProgress: (Double) -> Void
    ) async throws -> [SubtitleCue] {
        guard !cues.isEmpty else { return cues }

        var translations: [Int: String] = [:]
        var failures = 0

        for (index, cue) in cues.enumerated() {
            try Task.checkCancellation()

            let source = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }

            do {
                let response = try await session.translate(source)
                translations[index] = response.targetText
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One refused line should not abandon the whole file; it keeps its
                // source text on merge. A wholesale failure is caught after the loop.
                failures += 1
            }

            onProgress(Double(index + 1) / Double(cues.count))
        }

        guard !translations.isEmpty else {
            throw failures > 0
                ? SubtitleTranslationError.languagePairUnavailable
                : SubtitleTranslationError.translationFailed
        }

        return SubtitleTranslationAssembler.merge(
            cues: cues,
            translations: translations,
            output: output
        )
    }

    /// Whether the pair can be translated on this Mac. A `.supported` result still
    /// means assets may need downloading — the session prompts for that itself.
    @MainActor
    static func isPairAvailable(from source: Locale.Language, to target: Locale.Language) async -> Bool {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed, .supported:
            true
        case .unsupported:
            false
        @unknown default:
            false
        }
    }
}
