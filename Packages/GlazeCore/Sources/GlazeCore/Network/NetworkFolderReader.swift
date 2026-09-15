import Foundation

/// One thing found in a folder on a server.
public struct NetworkFolderEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case folder
        case film(NetworkMediaResource, ParsedMediaTitle)
        /// Something that is neither, carrying its extension so a platform that knows
        /// about books can decide what to do with it. The reader deliberately does not
        /// know: only the phone has a bookshelf, and the television must not carry the
        /// code behind one (`docs/32`).
        case file(extension: String)
    }

    /// The server's own address for this entry: a DSM path, a WebDAV URL, a UPnP
    /// object id. Opaque to everything above; only the reader interprets it.
    public let path: String
    public let name: String
    public let kind: Kind
    public let byteCount: Int64?
    /// Artwork sitting beside a film. Never fetched unless a layout asks for it.
    public let posterURL: URL?

    public var id: String { path }
    public var isFolder: Bool { kind == .folder }

    public var displayName: String {
        if case .film(_, let parsed) = kind { return parsed.listTitle }
        return name
    }

    public init(
        path: String,
        name: String,
        kind: Kind,
        byteCount: Int64? = nil,
        posterURL: URL? = nil
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.byteCount = byteCount
        self.posterURL = posterURL
    }
}

/// Walks a server one folder at a time, whichever kind of server it is.
///
/// The library used to be built by descending the whole tree from whichever folder was
/// chosen, counting folders as it went, and doing it again on every connect. On a NAS
/// with a few thousand films that is thousands of requests before anything appears —
/// and the result was thrown away when the app closed.
///
/// This asks for exactly the folder being looked at. Opening one is a single request
/// however much sits beneath it, and nothing is read that nobody looked at.
///
/// Shared by all three platforms on purpose: the phone, the television and the Mac were
/// each growing their own way of listing the same three kinds of server.
public struct NetworkFolderReader: Sendable {
    public enum Backend: Sendable {
        case synology(session: SynologySession)
        case webDAV(connection: WebDAVConnection, password: String?)
        case dlna(server: NetworkMediaServer)
    }

    public let serverName: String
    public let backend: Backend
    /// Where browsing starts: the share the viewer chose, the WebDAV root, or the
    /// server's video root.
    public let rootPath: String

    public init(serverName: String, backend: Backend, rootPath: String) {
        self.serverName = serverName
        self.backend = backend
        self.rootPath = rootPath
    }

    /// Everything directly in one folder. Folders first, then everything else, each
    /// group in the order a person numbers files.
    public func read(_ path: String) async throws -> [NetworkFolderEntry] {
        let target = path.isEmpty ? rootPath : path
        let entries: [NetworkFolderEntry] = switch backend {
        case .synology(let session): try await readSynology(target, session: session)
        case .webDAV(let connection, let password):
            try await readWebDAV(target, connection: connection, password: password)
        case .dlna(let server): try await readDLNA(target, server: server)
        }
        return sort(entries)
    }

    // MARK: - Synology

    private func readSynology(
        _ path: String,
        session: SynologySession
    ) async throws -> [NetworkFolderEntry] {
        let client = SynologyClient()
        // An empty root means no folder was ever chosen: show the shares.
        let listing = path.isEmpty
            ? try await client.shares(session)
            : try await client.list(path, session: session)

        let names = listing.map(\.name)
        return listing.compactMap { entry in
            guard !entry.isDirectory else {
                return NetworkFolderEntry(path: entry.path, name: entry.name, kind: .folder)
            }
            let folder = entry.path.split(separator: "/").dropLast().joined(separator: "/")
            return file(
                name: entry.name,
                path: entry.path,
                byteCount: entry.byteCount,
                siblings: names,
                url: { client.mediaURL(for: $0, session: session) },
                siblingPath: { "/\(folder)/\($0)".replacingOccurrences(of: "//", with: "/") }
            )
        }
    }

    // MARK: - WebDAV

    private func readWebDAV(
        _ path: String,
        connection: WebDAVConnection,
        password: String?
    ) async throws -> [NetworkFolderEntry] {
        guard let url = URL(string: path) else { return [] }
        let credentials = password.map { (username: connection.username, password: $0) }
        let listing = try await WebDAVClient().list(url, credentials: credentials)

        let names = listing.map(\.name)
        return listing.compactMap { entry in
            guard !entry.isDirectory else {
                return NetworkFolderEntry(
                    path: entry.url.absoluteString,
                    name: entry.name,
                    kind: .folder
                )
            }
            return file(
                name: entry.name,
                path: entry.url.absoluteString,
                byteCount: entry.byteCount,
                siblings: names,
                url: { URL(string: $0) ?? entry.url },
                siblingPath: {
                    entry.url.deletingLastPathComponent().appendingPathComponent($0).absoluteString
                }
            )
        }
    }

    // MARK: - DLNA

    /// A UPnP server answers with the resource already resolved, so there is nothing to
    /// assemble here — and no sibling listing to find subtitles in, because the server
    /// reports those itself or not at all.
    private func readDLNA(
        _ objectID: String,
        server: NetworkMediaServer
    ) async throws -> [NetworkFolderEntry] {
        let nodes = try await UPnPContentDirectoryClient().browse(
            server: server,
            objectID: objectID.isEmpty ? "0" : objectID
        )
        return nodes.compactMap { node in
            switch node.kind {
            case .container:
                NetworkFolderEntry(path: node.id, name: node.title, kind: .folder)
            case .video(let resource):
                NetworkFolderEntry(
                    path: node.id,
                    name: node.title,
                    kind: .film(resource, MediaTitleParser.parse(node.title)),
                    byteCount: resource.byteCount
                )
            case .unsupported:
                nil
            }
        }
    }

    // MARK: - Shared

    /// Turns one listed file into an entry, finding its subtitles and poster among the
    /// names the same listing already returned — so a folder still costs one request.
    ///
    /// The `.nfo` beside a film is deliberately **not** fetched: that would be one more
    /// request per film in the folder, which is the cost this exists to avoid. The name
    /// is parsed instead, and an information screen can read the `.nfo` for the one
    /// film someone actually asks about.
    private func file(
        name: String,
        path: String,
        byteCount: Int64?,
        siblings: [String],
        url: (String) -> URL,
        siblingPath: (String) -> String
    ) -> NetworkFolderEntry? {
        let ending = (name as NSString).pathExtension.lowercased()

        guard MediaFileTypes.video.contains(ending) else {
            // Subtitles, `.nfo`s and artwork belong to a film rather than standing on
            // their own, and a listing that shows them is noise.
            guard !Self.companionExtensions.contains(ending) else { return nil }
            return NetworkFolderEntry(
                path: path,
                name: name,
                kind: .file(extension: ending),
                byteCount: byteCount
            )
        }

        let companions = MediaCompanionFinder.find(videoName: name, among: siblings)
        let resource = NetworkMediaResource(
            serverID: serverName,
            objectID: path,
            playbackURL: url(path),
            byteCount: byteCount,
            duration: nil,
            dateAdded: nil,
            subtitleResources: companions.subtitles.map { subtitle in
                NetworkSubtitleResource(
                    url: url(siblingPath(subtitle)),
                    displayName: subtitle,
                    languageCode: SubtitleFile.manual(url: URL(fileURLWithPath: subtitle)).languageCode
                )
            }
        )
        return NetworkFolderEntry(
            path: path,
            name: name,
            kind: .film(resource, MediaTitleParser.parse(name)),
            byteCount: byteCount,
            posterURL: companions.poster.map { url(siblingPath($0)) }
        )
    }

    private static let companionExtensions: Set<String> = [
        "srt", "ass", "ssa", "vtt", "sub", "idx", "smi", "nfo",
        "jpg", "jpeg", "png", "webp", "tbn"
    ]

    private func sort(_ entries: [NetworkFolderEntry]) -> [NetworkFolderEntry] {
        let byName = { (left: NetworkFolderEntry, right: NetworkFolderEntry) in
            left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
        }
        return entries.filter(\.isFolder).sorted(by: byName)
            + entries.filter { !$0.isFolder }.sorted(by: byName)
    }
}
