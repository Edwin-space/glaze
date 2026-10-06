import Foundation

public extension NetworkFolderReader {
    /// Where a corrected record for one film on this server can be written — or nil
    /// when this kind of server cannot be written to at all.
    ///
    /// Only WebDAV answers. A DLNA server has no write verb in the protocol: it is a
    /// catalogue, not a filesystem. Synology over DSM could in principle take a
    /// FileStation upload, but that is a different API from the one the browser signs
    /// in with, so until it is built the honest answer is no.
    ///
    /// Returning nil rather than throwing later is deliberate: the screen can say up
    /// front that the answer will not be saved, instead of letting someone search,
    /// choose and confirm before finding out.
    ///
    /// - Parameter path: the server's own address for the film, as it came back in a
    ///   `NetworkFolderEntry`. Only the reader knows how to read one.
    func sidecarDestination(forFilmAt path: String) -> (any SidecarDestination)? {
        switch backend {
        case .webDAV(let connection, let password):
            guard let url = URL(string: path) else { return nil }
            return WebDAVSidecarDestination(
                besideVideoAt: url,
                credentials: password.map { (username: connection.username, password: $0) }
            )
        case .synology, .dlna:
            return nil
        }
    }
}
