import Foundation

/// Converts between the subtitle size a person chooses and the one VLC accepts.
///
/// Everything above the player speaks in percent, because "125%" is what someone
/// setting subtitle size means. VLC takes a fraction — 1.0 is normal size — and
/// **asserts** on anything outside 0.1...5, which is a crash in a debug build of
/// libVLC and a silently wrong size elsewhere. Both players passed the percentage
/// straight through until this existed, asking for sizes a hundred times too large.
public enum SubtitleScale: Sendable {
    /// The size the interface offers, as a percentage of normal.
    public static let normalPercent: Float = 100
    public static let minimumPercent: Float = 75
    public static let maximumPercent: Float = 160

    /// VLC's own limits, from `vlc_player_SetSubtitleTextScale`.
    static let minimumFraction: Float = 0.1
    static let maximumFraction: Float = 5

    /// - Returns: the fraction VLC wants, clamped into the range it will accept.
    public static func fraction(fromPercent percent: Float) -> Float {
        min(max(percent / 100, minimumFraction), maximumFraction)
    }

    /// - Returns: the percentage to show, from whatever VLC reports back.
    public static func percent(fromFraction fraction: Float) -> Float {
        fraction * 100
    }

    /// Keeps a requested size inside what the interface offers before it is converted.
    public static func clampPercent(_ percent: Float) -> Float {
        min(max(percent, minimumPercent), maximumPercent)
    }
}
