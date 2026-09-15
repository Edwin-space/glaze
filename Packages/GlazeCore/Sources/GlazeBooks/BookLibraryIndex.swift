import Foundation
import GlazeCore

/// Turns a flat list of book files into a shelf.
///
/// The same idea as `MediaLibraryIndex`, and for the same reason: twenty-four
/// volumes of one manga are one thing on a shelf, not twenty-four. A book with no
/// siblings stays where it is — grouping a single volume into a "collection" of one
/// only adds a screen to tap through.
public enum BookLibraryIndex {
    /// Below this a shared title is a coincidence, not a run of volumes.
    private static let minimumVolumesInCollection = 2

    public static func build(from items: [BookItem]) -> BookLibrary {
        var byTitle: [String: [BookItem]] = [:]
        var standalone: [BookItem] = []

        for item in items {
            // Everything out of one archive is one run, however its folders are
            // named. Waiting for a volume number to agree would scatter a download
            // whose parts are called `제1화` or `ch01` across the whole shelf.
            if let key = item.collectionKey {
                byTitle["archive:\(key)", default: []].append(item)
                continue
            }
            guard item.volume != nil else {
                standalone.append(item)
                continue
            }
            byTitle[MediaLibraryIndex.groupingKey(for: item.title), default: []].append(item)
        }

        var collections: [BookCollection] = []
        for (key, volumes) in byTitle {
            guard volumes.count >= minimumVolumesInCollection else {
                standalone.append(contentsOf: volumes)
                continue
            }
            collections.append(
                BookCollection(
                    id: key,
                    // Keep the longest spelling seen, the way the series shelf does:
                    // one file dropping a subtitle should not rename the whole run.
                    title: volumes.map(\.title).max { $0.count < $1.count } ?? key,
                    volumes: volumes.sorted(by: byVolume)
                )
            )
        }

        collections.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        standalone.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }

        return BookLibrary(
            books: standalone,
            collections: collections,
            recentlyAdded: recentlyAdded(books: standalone, collections: collections)
        )
    }

    private static func byVolume(_ left: BookItem, _ right: BookItem) -> Bool {
        let leftNumber = left.volume ?? Int.max
        let rightNumber = right.volume ?? Int.max
        if leftNumber != rightNumber { return leftNumber < rightNumber }
        // Unnumbered parts of one archive still have an order: the one their folders
        // are in, read the way a person reads numbers.
        let leftName = left.archiveSection ?? left.fileName
        let rightName = right.archiveSection ?? right.fileName
        return leftName.localizedStandardCompare(rightName) == .orderedAscending
    }

    /// Only files the filesystem actually dated, and a collection counts once — a
    /// whole run copied over in one evening is one thing that happened.
    private static func recentlyAdded(
        books: [BookItem],
        collections: [BookCollection],
        limit: Int = 20
    ) -> [BookShelfEntry] {
        let entries = books.map(BookShelfEntry.book) + collections.map(BookShelfEntry.collection)
        return entries
            .filter { $0.dateAdded != nil }
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }
}
