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

public protocol NetworkMediaServerDiscovering: Sendable {
    func discoverServers() async throws -> [NetworkMediaServer]
}

public protocol NetworkMediaServerBrowsing: Sendable {
    func browse(server: NetworkMediaServer, objectID: String) async throws -> [NetworkMediaNode]
}
