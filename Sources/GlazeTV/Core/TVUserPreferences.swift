import Foundation
import GlazeCore
import Observation

/// Preferences that affect the ten-foot viewing experience.
///
/// These values deliberately use locale-independent language codes. They can later
/// move to iCloud key-value storage without changing the player or settings views.
@MainActor
@Observable
final class TVUserPreferences {
    private enum Key {
        static let onboardingCompleted = "tv.onboarding.completed"
        static let preferredServerID = "tv.media.preferredServerID"
        static let defaultSubtitleLanguage = "tv.subtitle.defaultLanguage"
        static let automaticallySelectSubtitles = "tv.subtitle.automaticallySelect"
        static let subtitleScale = "tv.subtitle.scale"
    }

    private let defaults: UserDefaults

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
    }

    var preferredServerID: String? {
        didSet { defaults.set(preferredServerID, forKey: Key.preferredServerID) }
    }

    var defaultSubtitleLanguageCode: String {
        didSet { defaults.set(defaultSubtitleLanguageCode, forKey: Key.defaultSubtitleLanguage) }
    }

    var automaticallySelectSubtitles: Bool {
        didSet { defaults.set(automaticallySelectSubtitles, forKey: Key.automaticallySelectSubtitles) }
    }

    var subtitleScale: Float {
        didSet { defaults.set(subtitleScale, forKey: Key.subtitleScale) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
        preferredServerID = defaults.string(forKey: Key.preferredServerID)
        defaultSubtitleLanguageCode = defaults.string(forKey: Key.defaultSubtitleLanguage)
            ?? SubtitleLanguagePreference.targetLanguageCode
        automaticallySelectSubtitles = defaults.object(forKey: Key.automaticallySelectSubtitles) as? Bool ?? true
        let storedScale = defaults.float(forKey: Key.subtitleScale)
        subtitleScale = storedScale > 0 ? storedScale : 100
    }

    func finishOnboarding(serverID: String?) {
        preferredServerID = serverID
        onboardingCompleted = true
    }

    func restartOnboarding() {
        onboardingCompleted = false
    }
}

struct TVSubtitleLanguage: Identifiable, Hashable {
    let id: String

    var localizedName: String {
        Locale.current.localizedString(forLanguageCode: id)?.capitalized ?? id.uppercased()
    }

    static let supported: [TVSubtitleLanguage] = [
        "ko", "en", "ja", "zh", "es", "fr", "de", "it", "pt"
    ].map(TVSubtitleLanguage.init(id:))
}
