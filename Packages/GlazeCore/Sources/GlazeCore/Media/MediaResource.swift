import Foundation

public enum MediaResource: Equatable, Hashable, Sendable {
    case localFile(URL)
    case network(NetworkMediaResource)

    public var playbackURL: URL {
        switch self {
        case .localFile(let url):
            url
        case .network(let resource):
            resource.playbackURL
        }
    }

    /// The file on this Mac, when there is one. A streamed video has no folder to read
    /// subtitles from or write them into, and no sandbox permission to inherit.
    public var localFileURL: URL? {
        switch self {
        case .localFile(let url):
            url
        case .network:
            nil
        }
    }

    public var isNetwork: Bool {
        if case .network = self { return true }
        return false
    }
}

public struct NetworkMediaResource: Equatable, Hashable, Sendable {
    public let serverID: String
    public let objectID: String
    public let playbackURL: URL
    public let mimeType: String?
    public let protocolInfo: String?
    public let byteCount: Int64?
    public let duration: TimeInterval?
    /// e.g. `1920x816`, straight from the server. DLNA sends no artwork, so the few
    /// facts it does send have to carry the shelf.
    public let resolution: String?
    /// When the server first saw the file. The only thing available to order a
    /// "recently added" shelf by.
    public let dateAdded: Date?
    /// Subtitle files exposed beside a network video. DLNA normally cannot provide
    /// these, while WebDAV can derive them from the directory listing it already has.
    /// The player downloads them after playback starts so subtitle preparation never
    /// delays the first frame.
    public let subtitleResources: [NetworkSubtitleResource]

    public init(
        serverID: String,
        objectID: String,
        playbackURL: URL,
        mimeType: String? = nil,
        protocolInfo: String? = nil,
        byteCount: Int64? = nil,
        duration: TimeInterval? = nil,
        resolution: String? = nil,
        dateAdded: Date? = nil,
        subtitleResources: [NetworkSubtitleResource] = []
    ) {
        self.serverID = serverID
        self.objectID = objectID
        self.playbackURL = playbackURL
        self.mimeType = mimeType
        self.protocolInfo = protocolInfo
        self.byteCount = byteCount
        self.duration = duration
        self.resolution = resolution
        self.dateAdded = dateAdded
        self.subtitleResources = subtitleResources
    }
}

public struct NetworkSubtitleResource: Equatable, Hashable, Sendable {
    public let url: URL
    public let displayName: String
    public let languageCode: String?

    public init(url: URL, displayName: String, languageCode: String? = nil) {
        self.url = url
        self.displayName = displayName
        self.languageCode = SubtitleLanguageCode.normalized(languageCode)
    }
}
