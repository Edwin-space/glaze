import SwiftUI

enum SubtitleStatus {
    case noVideo
    case noSubtitle
    case subtitleDetected
    case koreanSubtitleDetected
    case subtitleLoaded
    case readyToGenerate
    case generating
    case translating

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
        case .translating:
            "subtitle.status.translating"
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
        case .translating:
            "character.bubble"
        }
    }

    var tint: Color {
        switch self {
        case .noVideo:
            .secondary
        case .noSubtitle:
            .orange
        case .subtitleDetected:
            .green
        case .koreanSubtitleDetected:
            .green
        case .subtitleLoaded:
            .green
        case .readyToGenerate:
            .accentColor
        case .generating:
            .accentColor
        case .translating:
            .accentColor
        }
    }
}
