import Foundation
import GlazeBooks
import GlazeCore
import Observation

/// Holds the connection the network tab is browsing.
///
/// The walking itself is `NetworkFolderReader` in `GlazeCore`, shared with the Apple
/// TV: the three kinds of server behave the same and there is no reason for two apps to
/// each learn that separately. What is left here is what the phone needs on top —
/// remembering which server is open, and deciding that a `.cbz` is a book, which is a
/// judgement only the phone has a reader for.
@MainActor
@Observable
final class IOSNetworkBrowser {
    private(set) var reader: NetworkFolderReader?

    var isConnected: Bool { reader != nil }
    var serverName: String { reader?.serverName ?? "" }
    var rootPath: String { reader?.rootPath ?? "" }

    func use(synology name: String, session: SynologySession, rootPath: String) {
        reader = NetworkFolderReader(
            serverName: name,
            backend: .synology(session: session),
            rootPath: rootPath
        )
    }

    func use(webDAV connection: WebDAVConnection, password: String?) {
        reader = NetworkFolderReader(
            serverName: connection.name,
            backend: .webDAV(connection: connection, password: password),
            rootPath: connection.rootURL.absoluteString
        )
    }

    /// A UPnP server is browsed by object id, and `"0"` is the root every one of them
    /// answers to.
    func use(dlna server: NetworkMediaServer) {
        reader = NetworkFolderReader(
            serverName: server.friendlyName,
            backend: .dlna(server: server),
            rootPath: "0"
        )
    }

    func disconnect() { reader = nil }

    func read(_ path: String) async throws -> [IOSNetworkEntry] {
        guard let reader else { return [] }
        return try await reader.read(path).map(IOSNetworkEntry.init)
    }
}

/// A folder entry as the phone sees it: the shared reading, plus the one thing the
/// phone knows that the shared code deliberately does not.
struct IOSNetworkEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder
        case film(NetworkMediaResource, ParsedMediaTitle)
        case book
        case other
    }

    let path: String
    let name: String
    let kind: Kind
    let byteCount: Int64?
    let posterURL: URL?

    var id: String { path }
    var isFolder: Bool { kind == .folder }
    var displayName: String {
        if case .film(_, let parsed) = kind { return parsed.listTitle }
        return name
    }

    init(_ entry: NetworkFolderEntry) {
        path = entry.path
        name = entry.name
        byteCount = entry.byteCount
        posterURL = entry.posterURL
        kind = switch entry.kind {
        case .folder: .folder
        case .film(let resource, let parsed): .film(resource, parsed)
        case .file(let ending): BookFileTypes.all.contains(ending) ? .book : .other
        }
    }
}
