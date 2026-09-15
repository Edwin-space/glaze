import Foundation
import GlazeCore

/// Lists folders on a server, for the picker.
///
/// Two servers, one shape. The picker does not need to know which it is talking to,
/// and neither protocol needs to know there is a picker.
enum IOSRemoteFolders {
    static func webDAV(
        connection: WebDAVConnection,
        password: String?
    ) -> (String) async throws -> [IOSRemoteFolder] {
        { path in
            let credentials = password.map { (username: connection.username, password: $0) }
            let url = path.isEmpty
                ? connection.rootURL
                : path.split(separator: "/").reduce(connection.rootURL) { $0.appendingPathComponent(String($1)) }

            let entries = try await WebDAVClient().list(url, credentials: credentials)
            return entries
                .filter { $0.isDirectory && !$0.isHidden }
                .map { IOSRemoteFolder(path: path.isEmpty ? $0.name : "\(path)/\($0.name)", name: $0.name) }
        }
    }

    static func synology(session: SynologySession) -> (String) async throws -> [IOSRemoteFolder] {
        { path in
            let client = SynologyClient()
            // DSM's root is the list of shares rather than a folder that can be listed.
            guard !path.isEmpty else {
                return try await client.shares(session)
                    .filter { !$0.isHidden }
                    .map { IOSRemoteFolder(path: $0.path, name: $0.name) }
            }
            return try await client.list(path, session: session)
                .filter { $0.isDirectory && !$0.isHidden }
                .map { IOSRemoteFolder(path: $0.path, name: $0.name) }
        }
    }
}
