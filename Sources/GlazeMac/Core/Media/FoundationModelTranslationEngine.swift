import FoundationModels
import Foundation
import GlazeCore

/// Constrains the reply to a single field.
///
/// Asking the model in prose to "reply with the translation only" was not enough: it
/// returned the surrounding context translated as well, and redistribution then spread
/// four sentences across two cues. A schema removes the option at the decoder rather
/// than relying on the model to obey.
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

    /// How many neighbouring sentences to show the model as context. Enough for
    /// pronouns and register to carry, small enough to stay well inside the context
    /// window across a feature-length file.
    private static let contextWindow = 2

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

        // One session for the whole file: the instructions are stated once, and the
        // model keeps the same register from the first line to the last.
        let session = LanguageModelSession(instructions: instructions)
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

            let source = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else {
                results.append(nil)
                onProgress(Double(position + 1) / Double(segments.count))
                continue
            }

            do {
                let response = try await session.respond(
                    to: prompt(for: source, at: position, in: segments),
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

    /// Neighbouring lines go in as context so pronouns, tense, and register have
    /// something to agree with — the thing the system translator cannot be given.
    private func prompt(for source: String, at position: Int, in segments: [SubtitleSegment]) -> String {
        let start = max(0, position - Self.contextWindow)
        let end = min(segments.count - 1, position + Self.contextWindow)

        let before = (start..<position)
            .map { segments[$0].text.replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\n")
        let after = ((position + 1)...max(position + 1, end))
            .filter { $0 <= end && $0 < segments.count }
            .map { segments[$0].text.replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\n")

        // Context is labelled as background and kept away from the instruction, so
        // there is one unambiguous sentence to act on at the end of the prompt.
        var prompt = ""
        if !before.isEmpty || !after.isEmpty {
            let surrounding = [before, after].filter { !$0.isEmpty }.joined(separator: "\n")
            prompt += "Background — nearby dialogue, for tone only, do not translate:\n"
            prompt += surrounding
            prompt += "\n\n"
        }
        prompt += "Translate this sentence:\n\(source)"
        return prompt
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
