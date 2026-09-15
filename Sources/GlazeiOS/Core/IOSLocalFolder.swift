import Foundation
import GlazeBooks
import GlazeCore

/// Reads one folder on the device — no deeper than it has to.
///
/// The library loader walks the whole tree to build shelves. A browser wants the
/// opposite: what is directly here, now, so opening a folder is instant however much
/// sits below it.
enum IOSLocalFolder {
    static func read(_ folder: URL) -> [IOSLocalEntry] {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let names = children.map(\.lastPathComponent)
        var folders: [IOSLocalEntry] = []
        var films: [IOSLocalEntry] = []

        for child in children where !isSkipped(child) {
            if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let counts = count(below: child)
                folders.append(
                    IOSLocalEntry(url: child, kind: .folder(films: counts.films, books: counts.books))
                )
            } else if MediaFileTypes.isVideo(child) {
                films.append(IOSLocalEntry(url: child, kind: .film(item(for: child, siblings: names))))
            }
        }

        // Folders first, then films — the shape of every file browser people already
        // know, and it keeps a folder from hiding under a long list of episodes.
        return folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            + films.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// What to hand the player. The device needs no credentials, so this is the film's
    /// own address and whatever subtitles sit beside it.
    static func resource(for item: MediaLibraryItem) -> NetworkMediaResource {
        NetworkMediaResource(
            serverID: "device",
            objectID: item.id,
            playbackURL: item.playbackURL,
            byteCount: item.byteCount,
            duration: item.duration,
            dateAdded: item.dateAdded,
            subtitleResources: item.subtitleURLs.map { url in
                NetworkSubtitleResource(
                    url: url,
                    displayName: url.lastPathComponent,
                    languageCode: SubtitleFile.manual(url: url).languageCode
                )
            }
        )
    }

    private static func item(for video: URL, siblings: [String]) -> MediaLibraryItem {
        let folder = video.deletingLastPathComponent()
        let companions = MediaCompanionFinder.find(videoName: video.lastPathComponent, among: siblings)

        var nfo: MediaNFO?
        if let name = companions.nfo,
           let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
            nfo = MediaNFOParser.parse(data)
        }
        let values = try? video.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        return MediaLibraryItem(
            id: video.standardizedFileURL.path,
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

    /// Counted so a folder can say what is in it before it is opened. Books are counted
    /// as well as films: this browser shows every folder, including the one holding the
    /// shelf, and a folder full of comics saying only "폴더" would read as empty.
    /// Bounded, because this runs for every folder on screen.
    private static func count(below folder: URL, limit: Int = 500) -> (films: Int, books: Int) {
        guard let walker = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var films = 0
        var books = 0
        for case let url as URL in walker {
            if MediaFileTypes.isVideo(url) {
                films += 1
            } else if BookFileTypes.isBook(url) {
                books += 1
            }
            if films + books >= limit { break }
        }
        return (films, books)
    }

    /// AppleDouble files travel with anything copied from a Mac and are not films.
    private static func isSkipped(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasPrefix(".") || name.hasPrefix("._")
            || ["__macosx", "thumbs.db", "desktop.ini"].contains(name)
    }
}
