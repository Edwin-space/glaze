import Foundation

/// Reads a NAS share into a library.
///
/// A share is not one folder. `Movies/Parasite (2019)/parasite.mkv` and
/// `TV/The Bear/Season 01/...` are the shapes people actually keep, so a loader that
/// only listed the address it was given would find nothing but folders. This walks
/// them, and stops walking rather than crawling a whole NAS.
public actor WebDAVLibraryLoader {
    public struct Limits: Sendable {
        /// How far below the address to walk.
        ///
        /// A WebDAV root is the list of shared folders, so a film is already two levels
        /// down before the library even starts: `/video/Media/<Title>/<file>`. A series
        /// adds a season folder on top of that. Three stopped short of both.
        public var depth: Int
        /// A ceiling on the listing requests one load may make. High enough for a real
        /// library, low enough that a wrong address cannot walk a whole NAS.
        public var folders: Int

        public init(depth: Int = 5, folders: Int = 800) {
            self.depth = depth
            self.folders = folders
        }
    }

    private let client: WebDAVClient
    private let limits: Limits

    public init(client: WebDAVClient = WebDAVClient(), limits: Limits = Limits()) {
        self.client = client
        self.limits = limits
    }

    /// - Parameter onProgress: called with folders read so far, so a television can say
    ///   something truthful while a large share is being read.
    public func load(
        root: URL,
        credentials: (username: String, password: String)?,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> MediaLibrary {
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        var visited: Set<String> = []
        var items: [MediaLibraryItem] = []
        var foldersRead = 0

        while !queue.isEmpty, foldersRead < limits.folders {
            let (url, depth) = queue.removeFirst()
            guard visited.insert(url.absoluteString).inserted else { continue }

            let entries: [WebDAVEntry]
            do {
                entries = try await client.list(url, credentials: credentials)
            } catch WebDAVError.unauthorized {
                // Credentials are wrong for the whole share, not for one folder.
                throw WebDAVError.unauthorized
            } catch {
                // One unreadable folder should not lose the rest of the library.
                continue
            }
            foldersRead += 1
            onProgress?(foldersRead)

            // A PROPFIND answers with the folder itself as well as its children.
            let children = entries.filter { $0.url != url }
            if depth < limits.depth {
                queue.append(
                    contentsOf: children
                        .filter { $0.isDirectory && !$0.isHidden }
                        .map { ($0.url, depth + 1) }
                )
            }

            for video in children where !video.isDirectory && video.isVideo {
                let companions = WebDAVCompanionFinder.find(for: video, among: children)
                items.append(
                    await makeItem(video: video, companions: companions, credentials: credentials)
                )
            }
        }

        return MediaLibraryIndex.build(from: items)
    }

    private func makeItem(
        video: WebDAVEntry,
        companions: WebDAVCompanions,
        credentials: (username: String, password: String)?
    ) async -> MediaLibraryItem {
        var nfo: MediaNFO?
        if let nfoEntry = companions.nfo,
           let data = try? await client.fetch(nfoEntry.url, credentials: credentials, maximumBytes: 1_024 * 1_024) {
            nfo = MediaNFOParser.parse(data)
        }

        return MediaLibraryItem(
            id: video.url.absoluteString,
            sourceName: video.name,
            parsed: MediaTitleParser.parse(video.name),
            metadata: nfo,
            posterURL: companions.poster?.url,
            playbackURL: video.url,
            subtitleURLs: companions.subtitles.map(\.url),
            dateAdded: video.lastModified,
            byteCount: video.byteCount
        )
    }
}
