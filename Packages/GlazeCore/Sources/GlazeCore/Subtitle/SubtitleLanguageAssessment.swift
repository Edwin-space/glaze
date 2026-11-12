import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public struct SubtitleLanguageAssessment: Equatable, Sendable {
    public enum Origin: Equatable, Sendable { case content, metadata, unknown, user }
    public let languageCode: String?
    public let origin: Origin
    public let confidence: Double

    /// Bounded, evenly distributed samples prevent a title card or filename from
    /// deciding the language of a film. All recognition is local, with no AI task.
    public static func assess(cues: [SubtitleCue], declaredLanguageCode: String?) -> Self {
        let count = min(cues.count, 96)
        let samples = (0..<count).map { index in
            let offset = count > 1 ? index * (cues.count - 1) / (count - 1) : 0
            return String(cues[offset].text.prefix(256))
        }
        let text = String(samples.joined(separator: "\n").prefix(16_000))
        #if canImport(NaturalLanguage)
        // Bilingual Japanese/Korean captions already contain both scripts. Do not
        // confidently call those a foreign-language-only subtitle.
        let scalars = text.unicodeScalars
        let kana = scalars.filter { (0x3040...0x30FF).contains($0.value) }.count
        let hangul = scalars.filter { (0xAC00...0xD7AF).contains($0.value) }.count
        if min(kana, hangul) >= 12, Double(min(kana, hangul)) / Double(max(kana + hangul, 1)) >= 0.2 {
            return Self(languageCode: nil, origin: .unknown, confidence: 0)
        }
        var languages = Set<String>()
        let width = max(1, (samples.count + 2) / 3)
        for start in stride(from: 0, to: samples.count, by: width) {
            let part = samples[start..<min(start + width, samples.count)].joined(separator: "\n")
            if let result = recognize(part) { languages.insert(result.languageCode) }
        }
        if languages.count > 1 {
            return Self(languageCode: nil, origin: .unknown, confidence: 0)
        }
        if let result = recognize(text) {
            return Self(languageCode: result.languageCode, origin: .content, confidence: result.confidence)
        }
        #endif
        let declared = SubtitleLanguageCode.normalized(declaredLanguageCode)
        return Self(languageCode: declared, origin: declared == nil ? .unknown : .metadata, confidence: 0)
    }

    #if canImport(NaturalLanguage)
    private static func recognize(_ text: String) -> (languageCode: String, confidence: Double)? {
        guard text.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 30 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let ranked = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
        guard let first = ranked.first, first.value >= 0.8,
              first.value - (ranked.dropFirst().first?.value ?? 0) >= 0.2,
              let code = SubtitleLanguageCode.normalized(first.key.rawValue) else { return nil }
        return (code, first.value)
    }
    #endif
}
