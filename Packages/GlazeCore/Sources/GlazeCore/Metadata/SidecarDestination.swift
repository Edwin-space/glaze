import Foundation

/// Where the files that describe a film get written.
///
/// Two places, one shape: beside a film on disk, or beside a film on a NAS. The writer
/// composes the same `.nfo` and poster either way, which is what keeps a NAS library
/// and a local one describable by the same code.
public protocol SidecarDestination: Sendable {
    /// - Parameter name: the complete filename, e.g. `Parasite.2019.nfo`.
    func write(_ data: Data, named name: String) async throws
}

/// Beside a film in a folder the viewer opened.
public struct LocalSidecarDestination: SidecarDestination {
    private let videoURL: URL

    public init(videoURL: URL) {
        self.videoURL = videoURL
    }

    public func write(_ data: Data, named name: String) async throws {
        let destination = videoURL.deletingLastPathComponent().appendingPathComponent(name)
        do {
            // Written as a related item of the video, which is what the App Sandbox
            // grants when the viewer opened the film rather than the folder.
            try RelatedFileAccess.write(data, to: destination, relatedTo: videoURL)
        } catch {
            throw MediaSidecarWriter.WriteError.writeFailed
        }
    }
}

/// Beside a film on a NAS.
public struct WebDAVSidecarDestination: SidecarDestination {
    private let folderURL: URL
    private let credentials: (username: String, password: String)?
    private let client: WebDAVClient

    /// - Parameter folderURL: the folder the film sits in.
    public init(
        folderURL: URL,
        credentials: (username: String, password: String)?,
        client: WebDAVClient = WebDAVClient()
    ) {
        self.folderURL = folderURL
        self.credentials = credentials
        self.client = client
    }

    /// - Parameter videoURL: a film's own address; its folder is where sidecars go.
    public init(
        besideVideoAt videoURL: URL,
        credentials: (username: String, password: String)?,
        client: WebDAVClient = WebDAVClient()
    ) {
        self.init(
            folderURL: videoURL.deletingLastPathComponent(),
            credentials: credentials,
            client: client
        )
    }

    public func write(_ data: Data, named name: String) async throws {
        try await client.upload(
            data,
            to: folderURL.appendingPathComponent(name),
            credentials: credentials
        )
    }
}
