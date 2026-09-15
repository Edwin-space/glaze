import Foundation

/// Which of a film's neighbouring subtitle files to load by default.
///
/// The one in the viewer's language when there is one, otherwise the first. Lived in the
/// phone's code, which meant the television — playing the same folders — had to guess
/// at it separately.
public enum SubtitleChoice {
    public static func preferred(
        among resources: [NetworkSubtitleResource],
        language: String?
    ) -> URL? {
        guard !resources.isEmpty else { return nil }
        let wanted = language.flatMap(SubtitleLanguageCode.normalized)
            ?? SubtitleLanguagePreference.targetLanguageCode
        return resources.first { $0.languageCode.flatMap(SubtitleLanguageCode.normalized) == wanted }?.url
            ?? resources.first?.url
    }
}
