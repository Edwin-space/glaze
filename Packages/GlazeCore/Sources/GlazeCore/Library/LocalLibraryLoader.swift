import Foundation

/// Reads a folder on the device into a library of films.
///
/// The counterpart to `WebDAVLibraryLoader`, and deliberately the same shape: a film
/// copied onto an iPhone over USB sits in a folder with its subtitle and poster
/// beside it exactly as it did on the NAS, so it deserves the same treatment —
/// grouped into films and shows, with the subtitle the Mac wrote already attached.
///
/// Books in the same folder are `LocalBookLoader`'s job, in `GlazeBooks`. A television
/// has no bookshelf, and this module is the one every platform links.
public actor LocalLibraryLoader {
    public typealias Limits = LocalFolderWalker.Limits

    private let walker: LocalFolderWalker

    public init(limits: Limits = Limits(), fileManager: FileManager = .default) {
        walker = LocalFolderWalker(limits: limits, fileManager: fileManager)
    }

    /// - Parameter onProgress: called with folders read so far.
    public func load(
        root: URL,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> MediaLibrary {
        var items: [MediaLibraryItem] = []

        for scan in walker.walk(root: root, onProgress: onProgress) {
            let names = scan.fileNames
            for file in scan.files where MediaFileTypes.isVideo(file) {
                items.append(makeItem(video: file, siblings: names, root: root))
            }
        }
        return MediaLibraryIndex.build(from: items)
    }

    // MARK: - Reading

    private func makeItem(video: URL, siblings: [String], root: URL) -> MediaLibraryItem {
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
            id: LocalFolderWalker.identifier(for: video, root: root),
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
}
