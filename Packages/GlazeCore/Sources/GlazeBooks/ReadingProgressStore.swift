import Foundation
import GlazeCore
import Observation

/// Where every book was left off, as something the shelves watch.
///
/// `ReadingPositionStore` reads and writes `UserDefaults`, which nothing observes.
/// Closing a comic on page three therefore wrote the page down and left the shelf
/// showing no progress at all until the screen happened to be rebuilt. Holding the
/// same values here, in memory, is what makes the shelf notice.
@MainActor
@Observable
public final class ReadingProgressStore {
    public private(set) var pages: [String: Int] = [:]
    public private(set) var pageCounts: [String: Int] = [:]

    private let store: ReadingPositionStore

    public init(store: ReadingPositionStore = ReadingPositionStore()) {
        self.store = store
        pages = store.allPages()
        pageCounts = store.allPageCounts()
    }

    /// - Returns: the zero-based page to open at, or nil to start from the beginning.
    public func page(for bookID: String) -> Int? {
        guard let page = pages[bookID], page >= ReadingPositionStore.minimumResumePage else { return nil }
        return page
    }

    public func pageCount(for bookID: String) -> Int? { pageCounts[bookID] }

    /// How far through, for the bar under a cover.
    public func progress(for bookID: String) -> Double? {
        guard let count = pageCounts[bookID], count > 0, let page = page(for: bookID) else { return nil }
        return min(1, Double(page + 1) / Double(count))
    }

    /// - Parameter page: zero-based.
    public func record(page: Int, of pageCount: Int, for bookID: String) {
        store.rememberPageCount(pageCount, for: bookID)
        store.record(page: page, of: pageCount, for: bookID)
        pageCounts[bookID] = pageCount
        // A book read to the end is forgotten rather than stored, so reopening it
        // starts at the cover; the store decides, and this follows it.
        pages[bookID] = store.page(for: bookID)
    }

    public func forget(_ bookID: String) {
        store.forget(bookID)
        pages[bookID] = nil
    }
}
