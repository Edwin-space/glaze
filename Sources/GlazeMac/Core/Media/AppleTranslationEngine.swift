import Foundation
import GlazeCore
// TranslationSession is a non-Sendable class that has not been audited for Swift 6
// concurrency. Every call on it below stays on the main actor, which is where SwiftUI
// vends the session in the first place.
@preconcurrency import Translation

/// Subtitle translation through Apple's on-device Translation framework.
///
/// The default engine: nothing to install, the widest language coverage, and it works
/// on Macs without Apple Intelligence. Its ceiling is that the API is string in,
/// string out — there is no way to pass surrounding dialogue or fix a Korean speech
/// level — which is what the planned Foundation Models and external-endpoint engines
/// are for. Feeding it whole sentences via `SubtitleSegmenter` is what recovers most
/// of the quality available here.
@MainActor
struct AppleTranslationEngine: SubtitleTranslationEngine {
    let engineID: SubtitleTranslationEngineID = .appleTranslation

    /// Vended by SwiftUI's `.translationTask`; cannot be constructed directly.
    let session: TranslationSession

    func translate(
        segments: [SubtitleSegment],
        targetLanguageCode: String,
        onProgress: (Double) -> Void
    ) async throws -> [String?] {
        guard !segments.isEmpty else { return [] }

        var results: [String?] = []
        results.reserveCapacity(segments.count)
        var failures = 0
        var successes = 0

        for (position, segment) in segments.enumerated() {
            try Task.checkCancellation()

            let source = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else {
                results.append(nil)
                onProgress(Double(position + 1) / Double(segments.count))
                continue
            }

            do {
                // One request per sentence rather than per cue. The batch API takes and
                // returns non-Sendable types that cannot leave the main actor the
                // session lives on; a String in and a Sendable response back can.
                let response = try await session.translate(source)

                // The system translator returns the source unchanged when it decides a
                // sentence needs no work — a proper noun, a number, or a pair it cannot
                // actually handle. None of those count as a translated line, and if
                // every line comes back this way the run must report failure rather
                // than write the original text into a file named for another language.
                if SubtitleTranslationAssembler.isEchoOfSource(response.targetText, source) {
                    results.append(nil)
                } else {
                    results.append(response.targetText)
                    successes += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One refused sentence keeps its source text on assembly; only a total
                // failure is worth reporting to the user.
                results.append(nil)
                failures += 1
            }

            onProgress(Double(position + 1) / Double(segments.count))
        }

        guard successes > 0 else {
            throw failures > 0
                ? SubtitleTranslationError.languagePairUnavailable
                : SubtitleTranslationError.translationFailed
        }

        return results
    }

    /// Whether the pair can be translated on this Mac. A `.supported` result still
    /// means assets may need downloading — the session prompts for that itself.
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
