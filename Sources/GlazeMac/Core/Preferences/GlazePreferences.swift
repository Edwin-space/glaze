import Foundation
import GlazeCore
import Observation

/// Choices that outlive a single video.
///
/// These used to live on `SubtitleController`, which meant they could only be changed
/// while a video was open — there was nowhere to set a transcription model before
/// opening anything. Pulling them out lets the Settings window and the inspector edit
/// the same values rather than each keeping a copy.
@MainActor
@Observable
final class GlazePreferences {
    /// One instance for the app. The Settings scene is built separately from the
    /// player's view tree, so there is no shared parent to pass this down from.
    static let shared = GlazePreferences()

    private enum Key {
        static let transcriptionTier = "subtitle.transcriptionTier"
        static let translationEngine = "subtitle.translationEngine"
        static let translationQuality = "subtitle.translationQuality"
        static let translationOutput = "subtitle.translationOutput"
        static let storageLocation = "subtitle.storageLocation"
        static let textSize = "subtitle.textSize"
        static let position = "subtitle.position"
        static let background = "subtitle.background"
        static let tmdbAPIKey = "metadata.tmdbAPIKey"
    }

    /// Which Whisper model transcription runs on.
    var transcriptionTier: TranscriptionModelTier {
        didSet { store(transcriptionTier.rawValue, Key.transcriptionTier) }
    }

    var translationEngineID: SubtitleTranslationEngineID {
        didSet { store(translationEngineID.rawValue, Key.translationEngine) }
    }

    /// Only meaningful for the system translator; the on-device model is steered by
    /// its instructions instead.
    var translationQuality: SubtitleTranslationQuality {
        didSet { store(translationQuality.rawValue, Key.translationQuality) }
    }

    var translationOutput: SubtitleTranslationOutput {
        didSet { store(translationOutput.rawValue, Key.translationOutput) }
    }

    /// Where finished subtitles are written. Beside the video by default, which on a
    /// mounted NAS means the NAS — see `docs/21_media_server_vision.md`.
    var storageLocation: SubtitleStorageLocation {
        didSet { store(storageLocation.rawValue, Key.storageLocation) }
    }

    /// How subtitles look on the video. Kept here rather than on the player so the
    /// choice survives closing a film, which is the only way it is useful.
    var textSize: SubtitleTextSize {
        didSet { store(textSize.rawValue, Key.textSize) }
    }

    var position: SubtitlePosition {
        didSet { store(position.rawValue, Key.position) }
    }

    var background: SubtitleBackground {
        didSet { store(background.rawValue, Key.background) }
    }

    /// The viewer's own TMDB key. Not shipped with the app: the terms around
    /// commercial use of a bundled key are unsettled (`docs/23`), and a key someone
    /// created themselves is unambiguous.
    var tmdbAPIKey: String {
        didSet { store(tmdbAPIKey, Key.tmdbAPIKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transcriptionTier = Self.read(defaults, Key.transcriptionTier) ?? .default
        translationEngineID = Self.read(defaults, Key.translationEngine) ?? .appleTranslation
        translationQuality = Self.read(defaults, Key.translationQuality) ?? .default
        translationOutput = Self.read(defaults, Key.translationOutput) ?? .bilingual
        storageLocation = Self.read(defaults, Key.storageLocation) ?? .default
        textSize = Self.read(defaults, Key.textSize) ?? .default
        position = Self.read(defaults, Key.position) ?? .default
        background = Self.read(defaults, Key.background) ?? .default
        tmdbAPIKey = defaults.string(forKey: Key.tmdbAPIKey) ?? ""
    }

    private static func read<T: RawRepresentable>(_ defaults: UserDefaults, _ key: String) -> T?
    where T.RawValue == String {
        // Written as a closure rather than `T.init(rawValue:)`: passing the
        // initializer itself is a value crossing isolation, which Swift 6 warns about.
        defaults.string(forKey: key).flatMap { T(rawValue: $0) }
    }

    private func store(_ value: String, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
