import Foundation
import GlazeBooks
import GlazeCore
import Observation
import UIKit

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
        static let lastSource = "ios.library.lastSource"
        static let readingDirection = "ios.reading.direction"
        static let doublePageSpreads = "ios.reading.doublePage"
        static let readingTheme = "ios.reading.theme"
        static let readingFontScale = "ios.reading.fontScale"
        static let tmdbAPIKey = "ios.metadata.tmdbAPIKey"
        static let browseLayout = "ios.browse.layout"
        static let holdSpeed = "ios.playback.holdSpeed"
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

    /// The viewer's own TMDB key, empty until they paste one in.
    ///
    /// Not shipped with the app. TMDB's terms around redistributing a key are not
    /// settled for a paid app (`docs/23`), and a shared key would be rate-limited
    /// across every copy of Glaze in the world anyway.
    /// How much faster the film runs while a finger is held on the left or right of
    /// the picture. The gesture is borrowed from where people already know it; the
    /// multiplier is theirs to set because 2× is a comfortable skim for one person
    /// and a blur for another.
    var holdSpeed: Float {
        didSet { defaults.set(holdSpeed, forKey: Key.holdSpeed) }
    }

    static let holdSpeedOptions: [Float] = [1.5, 2, 3, 4]

    var tmdbAPIKey: String {
        didSet { defaults.set(tmdbAPIKey, forKey: Key.tmdbAPIKey) }
    }

    /// How a folder's contents are laid out. Remembered, because it is a way of
    /// working rather than a per-folder decision.
    ///
    /// The list by default, deliberately. It is the only one of the three that reads
    /// no artwork at all, so it costs nothing however many books there are — and a
    /// shelf that gets slower the more you put on it is the wrong default to ship.
    /// Anyone who wants to pick by picture is one tap away.
    var browseLayout: IOSBrowseLayout {
        didSet { defaults.set(browseLayout.rawValue, forKey: Key.browseLayout) }
    }

    /// Which library was open last, so the app comes back to it. Without this the
    /// app forgot the films on the device every time it was launched.
    var lastSource: String? {
        didSet { defaults.set(lastSource, forKey: Key.lastSource) }
    }

    /// Which way a comic opens, until a particular book says otherwise. Most of what
    /// people read on a phone here is Korean and Japanese, so the default is the one
    /// those are printed in.
    var readingDirection: ReadingDirection {
        didSet { defaults.set(readingDirection.rawValue, forKey: Key.readingDirection) }
    }

    /// Two pages side by side once the device is turned sideways. Off on a phone by
    /// default — two comic pages across five inches is not reading, it is squinting.
    var doublePageSpreads: Bool {
        didSet { defaults.set(doublePageSpreads, forKey: Key.doublePageSpreads) }
    }

    /// Only reflowable books get a paper colour; a comic page carries its own.
    var readingTheme: ReadingTheme {
        didSet { defaults.set(readingTheme.rawValue, forKey: Key.readingTheme) }
    }

    var readingFontScale: Double {
        didSet { defaults.set(readingFontScale, forKey: Key.readingFontScale) }
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
        holdSpeed = defaults.object(forKey: Key.holdSpeed) as? Float ?? 2
        lastSource = defaults.string(forKey: Key.lastSource)
        readingDirection = defaults.string(forKey: Key.readingDirection)
            .flatMap(ReadingDirection.init(rawValue:)) ?? .rightToLeft
        doublePageSpreads = defaults.object(forKey: Key.doublePageSpreads) as? Bool
            ?? (UIDevice.current.userInterfaceIdiom == .pad)
        readingTheme = defaults.string(forKey: Key.readingTheme)
            .flatMap(ReadingTheme.init(rawValue:)) ?? .dark
        let storedFontScale = defaults.double(forKey: Key.readingFontScale)
        readingFontScale = storedFontScale > 0
            ? ReadingFontScale.clamp(storedFontScale)
            : ReadingFontScale.default
        tmdbAPIKey = defaults.string(forKey: Key.tmdbAPIKey) ?? ""
        browseLayout = defaults.string(forKey: Key.browseLayout)
            .flatMap(IOSBrowseLayout.init(rawValue:)) ?? .list
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
