import Foundation

/// Reads a folder on the device into a library.
///
/// The counterpart to `WebDAVLibraryLoader`, and deliberately the same shape: a film
/// copied onto an iPhone over USB sits in a folder with its subtitle and poster
/// beside it exactly as it did on the NAS, so it deserves the same treatment —
/// grouped into films and shows, with the subtitle the Mac wrote already attached.
public actor LocalLibraryLoader {
    public struct Limits: Sendable {
        /// How far below the folder to walk. People do keep `Films/Title/file.mkv`.
        public var depth: Int
        /// A ceiling on how many folders one load will open.
        public var folders: Int

        public init(depth: Int = 5, folders: Int = 800) {
            self.depth = depth
            self.folders = folders
        }
    }

    private let limits: Limits
    private let fileManager: FileManager

    public init(limits: Limits = Limits(), fileManager: FileManager = .default) {
        self.limits = limits
        self.fileManager = fileManager
    }

    /// - Parameter onProgress: called with folders read so far.
    public func load(
        root: URL,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> MediaLibrary {
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        var visited: Set<String> = []
        var items: [MediaLibraryItem] = []
        var foldersRead = 0

        while !queue.isEmpty, foldersRead < limits.folders {
            let (folder, depth) = queue.removeFirst()
            guard visited.insert(folder.standardizedFileURL.path).inserted else { continue }

            let children = contents(of: folder)
            foldersRead += 1
            onProgress?(foldersRead)

            if depth < limits.depth {
                queue.append(contentsOf: children.directories.map { ($0, depth + 1) })
            }

            let names = children.files.map(\.lastPathComponent)
            for video in children.files where Self.isVideo(video) {
                items.append(makeItem(video: video, siblings: names))
            }
        }

        return MediaLibraryIndex.build(from: items)
    }

    // MARK: - Reading

    private func contents(of folder: URL) -> (directories: [URL], files: [URL]) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], []) }

        var directories: [URL] = []
        var files: [URL] = []
        for entry in entries where !Self.isSkipped(entry) {
            if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                directories.append(entry)
            } else {
                files.append(entry)
            }
        }
        return (directories, files)
    }

    private func makeItem(video: URL, siblings: [String]) -> MediaLibraryItem {
        let companions = MediaCompanionFinder.find(
            videoName: video.lastPathComponent,
            among: siblings
        )
        let folder = video.deletingLastPathComponent()

        var nfo: MediaNFO?
        if let name = companions.nfo,
           let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
            nfo = MediaNFOParser.parse(data)
        }

        let values = try? video.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        return MediaLibraryItem(
            id: video.standardizedFileURL.absoluteString,
            sourceName: video.lastPathComponent,
            parsed: MediaTitleParser.parse(video.lastPathComponent),
            metadata: nfo,
            posterURL: companions.poster.map(folder.appendingPathComponent),
            playbackURL: video,
            subtitleURLs: companions.subtitles.map(folder.appendingPathComponent),
            dateAdded: values?.contentModificationDate,
            byteCount: values?.fileSize.map(Int64.init)
        )
    }

    // MARK: - What counts

    static func isVideo(_ url: URL) -> Bool {
        MediaFileTypes.isVideo(url)
    }

    /// AppleDouble files travel with anything copied from a Mac and are not films.
    private static func isSkipped(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasPrefix(".") || name.hasPrefix("._") || skippedNames.contains(name)
    }

    private static let skippedNames: Set<String> = [
        ".ds_store", "__macosx", "thumbs.db", "desktop.ini"
    ]
}
