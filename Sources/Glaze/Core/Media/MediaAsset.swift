import Foundation

struct MediaAsset: Identifiable {
    let id: UUID
    let fileURL: URL
    let source: MediaLibrarySource
    var metadata: MediaMetadata
    var subtitleReadiness: SubtitleReadiness
    var watchProgress: WatchProgress

    init(fileURL: URL, source: MediaLibrarySource = .localFolder) {
        self.id = UUID()
        self.fileURL = fileURL
        self.source = source
        self.metadata = MediaMetadata(
            displayTitle: MediaAsset.titleCandidate(from: fileURL),
            originalTitle: nil,
            year: nil,
            externalIDs: MediaExternalIDs(),
            matchStatus: .notMatched
        )
        self.subtitleReadiness = .notChecked
        self.watchProgress = WatchProgress(position: 0, duration: 0)
    }

    var displayTitle: String {
        metadata.displayTitle
    }

    private static func titleCandidate(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MediaLibrarySource {
    case localFolder
    case nas
    case iCloud
    case mediaServer

    var labelKey: String {
        switch self {
        case .localFolder:
            "media.source.local"
        case .nas:
            "media.source.nas"
        case .iCloud:
            "media.source.icloud"
        case .mediaServer:
            "media.source.server"
        }
    }
}

struct MediaMetadata {
    var displayTitle: String
    var originalTitle: String?
    var year: Int?
    var externalIDs: MediaExternalIDs
    var matchStatus: MetadataMatchStatus
}

struct MediaExternalIDs {
    var imdbID: String?
    var tmdbID: String?
    var tvdbID: String?
}

enum MetadataMatchStatus {
    case notMatched
    case candidate
    case confirmed
    case failed

    var labelKey: String {
        switch self {
        case .notMatched:
            "assistant.metadata.not_matched"
        case .candidate:
            "assistant.metadata.candidate"
        case .confirmed:
            "assistant.metadata.confirmed"
        case .failed:
            "assistant.metadata.failed"
        }
    }
}

enum SubtitleReadiness {
    case notChecked
    case missing
    case externalLoaded
    case generated
    case translated

    var labelKey: String {
        switch self {
        case .notChecked:
            "assistant.subtitle.not_checked"
        case .missing:
            "assistant.subtitle.missing"
        case .externalLoaded:
            "assistant.subtitle.external_loaded"
        case .generated:
            "assistant.subtitle.generated"
        case .translated:
            "assistant.subtitle.translated"
        }
    }
}

struct WatchProgress {
    var position: TimeInterval
    var duration: TimeInterval
}
