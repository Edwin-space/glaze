import Foundation

/// The language the viewer reads.
///
/// Shared because both apps need it for different reasons: the Mac decides what to
/// translate into, and the Apple TV decides which of the subtitles sitting beside a
/// film to load.
public enum SubtitleLanguagePreference {
    public static var targetLanguageCode: String {
        Locale.preferredLanguages.compactMap(SubtitleLanguageCode.normalized).first ?? "en"
    }
}
