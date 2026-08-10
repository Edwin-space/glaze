import SwiftUI

enum SubtitleStatus {
    case noVideo
    case noSubtitle
    case subtitleDetected
    case koreanSubtitleDetected
    case subtitleLoaded
    case readyToGenerate
    case generating

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
        case .generating:
            "subtitle.status.generating"
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
        case .generating:
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
            GlazeColors.celadon
        case .koreanSubtitleDetected:
            GlazeColors.celadon
        case .subtitleLoaded:
            GlazeColors.celadon
        case .readyToGenerate:
            GlazeColors.accent
        case .generating:
            GlazeColors.accent
        }
    }
}
