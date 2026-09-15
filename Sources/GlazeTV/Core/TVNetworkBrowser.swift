import Foundation
import GlazeCore
import Observation

/// Holds the server the folder browser is walking.
///
/// The walking is `NetworkFolderReader` in `GlazeCore`, the same one the phone uses.
/// The television has no bookshelf, so anything that is not a film or a folder simply
/// is not shown here.
@MainActor
@Observable
final class TVNetworkBrowser {
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
        let root = connection.libraryPath.map {
            connection.rootURL.appendingPathComponent($0).absoluteString
        } ?? connection.rootURL.absoluteString
        reader = NetworkFolderReader(
            serverName: connection.name,
            backend: .webDAV(connection: connection, password: password),
            rootPath: root
        )
    }

    func use(dlna server: NetworkMediaServer) {
        reader = NetworkFolderReader(
            serverName: server.friendlyName,
            backend: .dlna(server: server),
            rootPath: "0"
        )
    }

    /// Folders and films only. A `.cbz` on the NAS is a real file, but nothing on this
    /// device can open one, and offering it would be a promise the television cannot
    /// keep.
    func read(_ path: String) async throws -> [NetworkFolderEntry] {
        guard let reader else { return [] }
        return try await reader.read(path).filter { entry in
            switch entry.kind {
            case .folder, .film: true
            case .file: false
            }
        }
    }
}
