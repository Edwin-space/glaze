import Foundation

/// How subtitles are drawn on the video.
///
/// Films are watched at arm's length on a laptop and across a room on a display, with
/// burned-in signage that a subtitle can land on top of. One fixed size and position
/// cannot serve all of that, so these three are the viewer's to set.
public enum SubtitleTextSize: String, Equatable, Sendable, CaseIterable, Codable {
    case small
    case medium
    case large
    case extraLarge

    public static let `default` = SubtitleTextSize.medium

    /// Point size for the subtitle text.
    public var pointSize: Double {
        switch self {
        case .small: 17
        case .medium: 21
        case .large: 27
        case .extraLarge: 34
        }
    }

    public var labelKey: String {
        switch self {
        case .small: "subtitle.appearance.size.small"
        case .medium: "subtitle.appearance.size.medium"
        case .large: "subtitle.appearance.size.large"
        case .extraLarge: "subtitle.appearance.size.extra_large"
        }
    }
}

public enum SubtitlePosition: String, Equatable, Sendable, CaseIterable, Codable {
    case bottom
    /// Lifted clear of burned-in signage and hard subtitles, which sit at the very
    /// bottom of the frame often enough to be worth a setting.
    case raised
    case top

    public static let `default` = SubtitlePosition.bottom

    public var labelKey: String {
        switch self {
        case .bottom: "subtitle.appearance.position.bottom"
        case .raised: "subtitle.appearance.position.raised"
        case .top: "subtitle.appearance.position.top"
        }
    }
}

public enum SubtitleBackground: String, Equatable, Sendable, CaseIterable, Codable {
    /// The glass plate the rest of the app is built from.
    case plate
    /// No plate; the text carries its own shadow so it stays readable on white.
    case none

    public static let `default` = SubtitleBackground.plate

    public var labelKey: String {
        switch self {
        case .plate: "subtitle.appearance.background.plate"
        case .none: "subtitle.appearance.background.none"
        }
    }
}
