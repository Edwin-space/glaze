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
}

public struct NetworkMediaResource: Equatable, Hashable, Sendable {
    public let serverID: String
    public let objectID: String
    public let playbackURL: URL
    public let mimeType: String?
    public let protocolInfo: String?
    public let byteCount: Int64?
    public let duration: TimeInterval?

    public init(
        serverID: String,
        objectID: String,
        playbackURL: URL,
        mimeType: String? = nil,
        protocolInfo: String? = nil,
        byteCount: Int64? = nil,
        duration: TimeInterval? = nil
    ) {
        self.serverID = serverID
        self.objectID = objectID
        self.playbackURL = playbackURL
        self.mimeType = mimeType
        self.protocolInfo = protocolInfo
        self.byteCount = byteCount
        self.duration = duration
    }
}
