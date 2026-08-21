import FoundationModels
import Foundation
import GlazeCore

/// Constrains the reply to a single field.
///
/// Asking the model in prose to "reply with the translation only" was not enough: it
/// returned the surrounding context translated as well, and redistribution then spread
/// four sentences across two cues. A schema removes the option at the decoder rather
/// than relying on the model to obey.
///
/// The schema alone did not settle it. As long as neighbouring lines appeared in the
/// prompt as background, the model would sometimes translate one of them instead of
/// the line it was asked for — the first line of a test file came back as the third
/// line's translation. The prompt is now the source line and nothing else; continuity
/// comes from the session transcript, which the model already carries between turns.
@Generable
private struct TranslatedLine {
    @Guide(description: "The translated line only. No original text, no notes, no quotes.")
    var translation: String
}

/// Subtitle translation through Apple's on-device language model.
///
/// Exists because the system translator is string in, string out: there is no way to
/// tell it that a whole film should keep one speech level, so Korean output drifts
/// between 해요체, 합쇼체, and 해라체 within a few lines. A language model can be told
/// once, in instructions, and hold it for the file.
///
/// Everything stays on the device. The trade is availability — this needs Apple
/// Intelligence turned on — so the system translator remains the default.
@MainActor
struct FoundationModelTranslationEngine: SubtitleTranslationEngine {
    let engineID: SubtitleTranslationEngineID = .appleFoundationModel

    let targetLanguageDisplayName: String

    /// The session is rebuilt this often.
    ///
    /// One session per file would be ideal — the model would remember the whole film —
    /// but the transcript grows with every line and a feature-length subtitle file runs
    /// to well over a thousand of them, which overruns the context window partway
    /// through. Rebuilding periodically bounds it; the instructions, which is where the
    /// register rule lives, are restated each time.
    private static let segmentsPerSession = 40

    /// A model that wanders off-task can produce something far longer than the line
    /// it was given; cap it rather than letting one bad response stall the run.
    private static let responseTokenLimit = 400

    static func availability() -> SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func translate(
        segments: [SubtitleSegment],
        targetLanguageCode: String,
        onProgress: (Double) -> Void
    ) async throws -> [String?] {
        guard !segments.isEmpty else { return [] }
        guard SystemLanguageModel.default.isAvailable else {
            throw SubtitleTranslationError.languagePairUnavailable
        }

        var session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(
            // Deterministic — a translation should not change between runs of the
            // same file, and sampling buys nothing here.
            sampling: .greedy,
            maximumResponseTokens: Self.responseTokenLimit
        )

        var results: [String?] = []
        results.reserveCapacity(segments.count)
        var successes = 0

        for (position, segment) in segments.enumerated() {
            try Task.checkCancellation()

            if position > 0, position % Self.segmentsPerSession == 0 {
                session = LanguageModelSession(instructions: instructions)
            }

            let source = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else {
                results.append(nil)
                onProgress(Double(position + 1) / Double(segments.count))
                continue
            }

            do {
                let response = try await session.respond(
                    to: source,
                    generating: TranslatedLine.self,
                    options: options
                )
                results.append(cleaned(response.content.translation))
                successes += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A refused or over-long line keeps its source text on assembly.
                results.append(nil)
            }

            onProgress(Double(position + 1) / Double(segments.count))
        }

        guard successes > 0 else {
            throw SubtitleTranslationError.translationFailed
        }

        return results
    }

    /// Deliberately short. The first version listed six rules and the model followed
    /// none of them reliably — a small on-device model holds one instruction far
    /// better than a list, and the schema now enforces the output shape anyway.
    private var instructions: String {
        """
        Translate film subtitles into \(targetLanguageDisplayName).
        Translate meaning exactly, including negation.
        Use one consistent, natural level of politeness for the whole film.
        """
    }

    /// Models sometimes wrap a reply in quotes or prefix it with a label even when
    /// told not to; strip the common shapes rather than showing them on screen.
    private func cleaned(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for label in ["Translation:", "번역:", "TRANSLATION:"] where result.hasPrefix(label) {
            result = String(result.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }

        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'")]
        for (open, close) in quotePairs
        where result.count >= 2 && result.first == open && result.last == close {
            result = String(result.dropFirst().dropLast())
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
