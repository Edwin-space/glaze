import SwiftUI

enum SubtitleStatus {
    case noVideo
    case noSubtitle
    case readyToGenerate

    var titleKey: String {
        switch self {
        case .noVideo:
            "subtitle.status.no_video"
        case .noSubtitle:
            "subtitle.status.no_subtitle"
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
        case .readyToGenerate:
            GlazeColors.accent
        }
    }
}
