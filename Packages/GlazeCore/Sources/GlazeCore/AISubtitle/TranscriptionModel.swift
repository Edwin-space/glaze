import Foundation

/// Which Whisper model transcription runs on.
///
/// Transcription quality is the upstream half of subtitle quality: a weak model
/// mishears a name, and no translation engine downstream can recover it. The tiers
/// trade speed and download size against accuracy so the choice can be measured
/// rather than guessed — see `docs/03_ai_subtitle_workflow.md`.
public enum TranscriptionModelTier: String, Equatable, Sendable, CaseIterable, Codable {
    case fast
    case balanced
    case accurate
    case maximum

    /// The default stays at `balanced`: fast enough to try on a whole film without a
    /// long wait, accurate enough that the result is worth translating.
    public static let `default` = TranscriptionModelTier.balanced

    /// WhisperKit model identifier. These names match the `whisperkit-coreml`
    /// repository; WhisperKit downloads the weights on first use and caches them.
    public var whisperModelName: String {
        switch self {
        case .fast: "openai_whisper-base"
        case .balanced: "openai_whisper-small"
        // Turbo keeps large-v3's accuracy with a much smaller decoder, which is the
        // best accuracy-per-second point on Apple Silicon.
        case .accurate: "openai_whisper-large-v3-v20240930_turbo"
        case .maximum: "openai_whisper-large-v3"
        }
    }

    public var labelKey: String {
        switch self {
        case .fast: "subtitle.model.tier.fast"
        case .balanced: "subtitle.model.tier.balanced"
        case .accurate: "subtitle.model.tier.accurate"
        case .maximum: "subtitle.model.tier.maximum"
        }
    }

    /// On-disk size of the download, so the cost of switching tiers is visible before
    /// the user commits to it.
    ///
    /// Measured, not estimated: `base` and `balanced` were checked against the cache
    /// WhisperKit actually writes. The first published guesses were well under —
    /// `balanced` alone is 464 MB, not the 250 MB first written here — and a number
    /// shown next to a download has to be one the user can trust.
    public var approximateDownloadMegabytes: Int {
        switch self {
        case .fast: 140       // measured
        case .balanced: 465   // measured
        case .accurate: 950   // estimated from the turbo weights; confirm when first fetched
        case .maximum: 1_900  // estimated; confirm when first fetched
        }
    }
}
