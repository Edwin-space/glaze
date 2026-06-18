import SwiftUI

enum SubtitleStatus {
    case noVideo
    case noSubtitle
    case subtitleDetected
    case koreanSubtitleDetected
    case subtitleLoaded
    case readyToGenerate

    var titleKey: String {
        switch self {
        case .noVideo:
            "subtitle.status.no_video"
        case .noSubtitle:
            "subtitle.status.no_subtitle"
        case .subtitleDetected:
            "subtitle.status.subtitle_detected"
        case .koreanSubtitleDetected:
            "subtitle.status.korean_subtitle_detected"
        case .subtitleLoaded:
            "subtitle.status.subtitle_loaded"
        case .readyToGenerate:
            "subtitle.status.ready_to_generate"
        }
    }

    var iconName: String {
        switch self {
        case .noVideo:
            "captions.bubble"
        case .noSubtitle:
            "captions.bubble"
        case .subtitleDetected:
            "captions.bubble.fill"
        case .koreanSubtitleDetected:
            "captions.bubble.fill"
        case .subtitleLoaded:
            "captions.bubble.fill"
        case .readyToGenerate:
            "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .noVideo:
            .secondary
        case .noSubtitle:
            GlazeColors.warning
        case .subtitleDetected:
            GlazeColors.positive
        case .koreanSubtitleDetected:
            GlazeColors.positive
        case .subtitleLoaded:
            GlazeColors.positive
        case .readyToGenerate:
            GlazeColors.accent
        }
    }
}
