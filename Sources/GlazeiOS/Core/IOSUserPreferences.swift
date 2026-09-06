import Foundation
import GlazeCore
import Observation

/// What the viewer has told the player once and should not have to say again.
///
/// Deliberately locale-independent codes, so these can move to iCloud key-value
/// storage later without the player or the settings sheet changing.
@MainActor
@Observable
final class IOSUserPreferences {
    private enum Key {
        static let defaultSubtitleLanguage = "ios.subtitle.defaultLanguage"
        static let automaticallySelectSubtitles = "ios.subtitle.automaticallySelect"
        static let subtitleScale = "ios.subtitle.scale"
        static let playbackRate = "ios.playback.rate"
    }

    private let defaults: UserDefaults

    var defaultSubtitleLanguageCode: String {
        didSet { defaults.set(defaultSubtitleLanguageCode, forKey: Key.defaultSubtitleLanguage) }
    }

    var automaticallySelectSubtitles: Bool {
        didSet { defaults.set(automaticallySelectSubtitles, forKey: Key.automaticallySelectSubtitles) }
    }

    var subtitleScale: Float {
        didSet { defaults.set(subtitleScale, forKey: Key.subtitleScale) }
    }

    /// Remembered across films: someone who watches at 1.25× wants that every time.
    var playbackRate: Float {
        didSet { defaults.set(playbackRate, forKey: Key.playbackRate) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultSubtitleLanguageCode = defaults.string(forKey: Key.defaultSubtitleLanguage)
            ?? SubtitleLanguagePreference.targetLanguageCode
        automaticallySelectSubtitles = defaults.object(forKey: Key.automaticallySelectSubtitles) as? Bool ?? true
        let storedScale = defaults.float(forKey: Key.subtitleScale)
        subtitleScale = storedScale > 0 ? storedScale : 100
        let storedRate = defaults.float(forKey: Key.playbackRate)
        playbackRate = storedRate > 0 ? storedRate : 1
    }
}

struct IOSSubtitleLanguage: Identifiable, Hashable {
    let id: String

    var localizedName: String {
        Locale.current.localizedString(forLanguageCode: id)?.capitalized ?? id.uppercased()
    }

    static let supported: [IOSSubtitleLanguage] = [
        "ko", "en", "ja", "zh", "es", "fr", "de", "it", "pt"
    ].map(IOSSubtitleLanguage.init(id:))
}
