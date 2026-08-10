import Foundation

public struct MediaAsset: Identifiable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let source: MediaLibrarySource
    public var metadata: MediaMetadata
    public var subtitleReadiness: SubtitleReadiness
    public var watchProgress: WatchProgress

    public init(fileURL: URL, source: MediaLibrarySource = .localFolder) {
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

    public var displayTitle: String {
        metadata.displayTitle
    }

    private static func titleCandidate(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum MediaLibrarySource: Sendable {
    case localFolder
    case nas
    case iCloud
    case mediaServer

    public var labelKey: String {
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

public struct MediaMetadata: Sendable {
    public var displayTitle: String
    public var originalTitle: String?
    public var year: Int?
    public var externalIDs: MediaExternalIDs
    public var matchStatus: MetadataMatchStatus
}

public struct MediaExternalIDs: Sendable {
    public var imdbID: String?
    public var tmdbID: String?
    public var tvdbID: String?

    public init(imdbID: String? = nil, tmdbID: String? = nil, tvdbID: String? = nil) {
        self.imdbID = imdbID
        self.tmdbID = tmdbID
        self.tvdbID = tvdbID
    }
}

public enum MetadataMatchStatus: Sendable {
    case notMatched
    case candidate
    case confirmed
    case failed

    public var labelKey: String {
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

public enum SubtitleReadiness: Sendable {
    case notChecked
    case missing
    case externalLoaded
    case generated
    case translated

    public var labelKey: String {
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

public struct WatchProgress: Sendable {
    public var position: TimeInterval
    public var duration: TimeInterval

    public init(position: TimeInterval, duration: TimeInterval) {
        self.position = position
        self.duration = duration
    }
}
