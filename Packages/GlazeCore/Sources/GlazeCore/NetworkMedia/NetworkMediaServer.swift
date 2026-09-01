import Foundation

public struct NetworkMediaServer: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let friendlyName: String
    public let descriptionURL: URL
    public let contentDirectoryControlURL: URL

    public init(
        id: String,
        friendlyName: String,
        descriptionURL: URL,
        contentDirectoryControlURL: URL
    ) {
        self.id = id
        self.friendlyName = friendlyName
        self.descriptionURL = descriptionURL
        self.contentDirectoryControlURL = contentDirectoryControlURL
    }
}

public struct NetworkMediaNode: Identifiable, Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case container(childCount: Int?)
        case video(NetworkMediaResource)
        case unsupported
    }

    public let id: String
    public let parentID: String
    public let title: String
    public let upnpClass: String?
    public let kind: Kind

    public init(id: String, parentID: String, title: String, upnpClass: String?, kind: Kind) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.upnpClass = upnpClass
        self.kind = kind
    }
}

public enum NetworkMediaContainerRelevance: Equatable, Sendable {
    case video
    case nonVideo
    case unknown
}

public extension NetworkMediaNode {
    /// UPnP servers often expose Music, Photos, and Videos as sibling containers.
    /// Item MIME types are reliable, but container classes vary between vendors, so
    /// only explicit media classes are decided here; generic folders are probed by the
    /// content-directory client before they reach a video-first UI.
    var containerRelevance: NetworkMediaContainerRelevance {
        guard case .container = kind else { return .unknown }
        let value = upnpClass?.lowercased() ?? ""

        if value.contains("video") || value.contains("movie") {
            return .video
        }
        if value.contains("audio")
            || value.contains("music")
            || value.contains("image")
            || value.contains("photo") {
            return .nonVideo
        }
        return .unknown
    }
}

public protocol NetworkMediaServerDiscovering: Sendable {
    func discoverServers() async throws -> [NetworkMediaServer]
}

public protocol NetworkMediaServerBrowsing: Sendable {
    func browse(server: NetworkMediaServer, objectID: String) async throws -> [NetworkMediaNode]
    func browseVideoRoots(server: NetworkMediaServer, objectID: String) async throws -> [NetworkMediaNode]
}

public extension NetworkMediaServerBrowsing {
    func browseVideoRoots(
        server: NetworkMediaServer,
        objectID: String = "0"
    ) async throws -> [NetworkMediaNode] {
        try await browse(server: server, objectID: objectID).filter { node in
            switch node.kind {
            case .video:
                true
            case .container:
                node.containerRelevance != .nonVideo
            case .unsupported:
                false
            }
        }
    }
}
