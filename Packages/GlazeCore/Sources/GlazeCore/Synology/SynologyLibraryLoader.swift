import Foundation

/// Reads a Synology shared folder into a library.
///
/// The third of the same shape, after WebDAV and the device's own folder: whatever a
/// film's subtitle and poster are stored on, they are found by the same rule and the
/// result is the same library.
public actor SynologyLibraryLoader {
    public struct Limits: Sendable {
        public var depth: Int
        public var folders: Int

        public init(depth: Int = 5, folders: Int = 800) {
            self.depth = depth
            self.folders = folders
        }
    }

    private let client: SynologyClient
    private let limits: Limits

    public init(client: SynologyClient = SynologyClient(), limits: Limits = Limits()) {
        self.client = client
        self.limits = limits
    }

    /// - Parameter root: a shared folder path such as `/video`, or any folder inside one.
    public func load(
        root: String,
        session: SynologySession,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> MediaLibrary {
        var queue: [(path: String, depth: Int)] = [(root, 0)]
        var visited: Set<String> = []
        var items: [MediaLibraryItem] = []
        var foldersRead = 0

        while !queue.isEmpty, foldersRead < limits.folders {
            let (path, depth) = queue.removeFirst()
            guard visited.insert(path).inserted else { continue }

            let children: [SynologyEntry]
            do {
                children = try await client.list(path, session: session)
            } catch SynologyError.badCredentials {
                // The session expired for the whole NAS, not for one folder.
                throw SynologyError.badCredentials
            } catch {
                // One unreadable folder should not lose the rest of the library.
                continue
            }
            foldersRead += 1
            onProgress?(foldersRead)

            if depth < limits.depth {
                queue.append(
                    contentsOf: children
                        .filter { $0.isDirectory && !$0.isHidden }
                        .map { ($0.path, depth + 1) }
                )
            }

            let names = children.filter { !$0.isDirectory && !$0.isHidden }.map(\.name)
            for video in children where video.isVideo {
                items.append(
                    await makeItem(video: video, siblingNames: names, folder: path, session: session)
                )
            }
        }

        return MediaLibraryIndex.build(from: items)
    }

    private func makeItem(
        video: SynologyEntry,
        siblingNames: [String],
        folder: String,
        session: SynologySession
    ) async -> MediaLibraryItem {
        let companions = MediaCompanionFinder.find(videoName: video.name, among: siblingNames)

        var nfo: MediaNFO?
        if let name = companions.nfo,
           let data = try? await client.fetch(
               Self.join(folder, name),
               session: session,
               maximumBytes: 1_024 * 1_024
           ) {
            nfo = MediaNFOParser.parse(data)
        }

        return MediaLibraryItem(
            id: video.path,
            sourceName: video.name,
            parsed: MediaTitleParser.parse(video.name),
            metadata: nfo,
            posterURL: companions.poster.map {
                client.mediaURL(for: Self.join(folder, $0), session: session)
            },
            playbackURL: client.mediaURL(for: video.path, session: session),
            subtitleURLs: companions.subtitles.map {
                client.mediaURL(for: Self.join(folder, $0), session: session)
            },
            dateAdded: video.modifiedAt,
            byteCount: video.byteCount
        )
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder.hasSuffix("/") ? folder + name : folder + "/" + name
    }
}
