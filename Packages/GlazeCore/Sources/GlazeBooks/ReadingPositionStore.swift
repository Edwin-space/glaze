import Foundation
import GlazeCore

/// Remembers which page each book was left on.
///
/// The film side has `PlaybackPositionStore` and this is its twin, kept separate
/// because the units are different in kind: seconds into a stream against a page in
/// a fixed count. Sharing one store would mean a resume value that means nothing
/// without knowing which sort of thing it came from.
public struct ReadingPositionStore {
    /// A book opened and closed on page one has not been started.
    public static let minimumResumePage = 1
    /// Past this, the book is finished and reopening should start at the beginning.
    public static let finishedThreshold = 0.98

    private let defaults: UserDefaults
    private let key = "reading.positions"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// - Returns: the zero-based page to open at, or nil to start from the beginning.
    public func page(for bookID: String) -> Int? {
        guard let stored = positions()[bookID], stored >= Self.minimumResumePage else { return nil }
        return stored
    }

    /// - Parameter page: zero-based.
    public func record(page: Int, of pageCount: Int, for bookID: String) {
        var all = positions()

        let isFinished = pageCount > 0 && Double(page + 1) / Double(pageCount) >= Self.finishedThreshold
        if isFinished || page < Self.minimumResumePage {
            guard all[bookID] != nil else { return }
            all[bookID] = nil
        } else {
            all[bookID] = page
        }

        defaults.set(all, forKey: key)
    }

    /// How far through, for the bar under a cover. Nil when nothing is stored.
    public func progress(for bookID: String, pageCount: Int) -> Double? {
        guard pageCount > 0, let page = page(for: bookID) else { return nil }
        return min(1, Double(page + 1) / Double(pageCount))
    }

    public func forget(_ bookID: String) {
        var all = positions()
        guard all.removeValue(forKey: bookID) != nil else { return }
        defaults.set(all, forKey: key)
    }

    /// The page count is learned by opening the book, so it is written down the first
    /// time and reused to draw progress without opening anything.
    public func rememberPageCount(_ count: Int, for bookID: String) {
        guard count > 0 else { return }
        var all = pageCounts()
        guard all[bookID] != count else { return }
        all[bookID] = count
        defaults.set(all, forKey: pageCountKey)
    }

    public func pageCount(for bookID: String) -> Int? {
        pageCounts()[bookID]
    }

    private var pageCountKey: String { "reading.pageCounts" }

    /// Everything stored, for the observable store that keeps the shelves in step.
    public func allPages() -> [String: Int] { positions() }
    public func allPageCounts() -> [String: Int] { pageCounts() }

    private func positions() -> [String: Int] {
        defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private func pageCounts() -> [String: Int] {
        defaults.dictionary(forKey: pageCountKey) as? [String: Int] ?? [:]
    }
}

/// How the pages turn.
///
/// Chosen by the viewer rather than guessed from the file. A webtoon and a scanned
/// manga are both a zip of images and telling them apart means reading aspect ratios
/// and hoping; getting that wrong mid-volume is worse than asking once.
public enum ReadingDirection: String, CaseIterable, Sendable {
    /// A western book or a PDF.
    case leftToRight
    /// Manga, and most Korean and Japanese scans: page one is on the right.
    case rightToLeft
    /// Webtoons: one continuous strip, scrolled rather than turned. Most of what is
    /// read in Korea is drawn this way, and cutting it into pages breaks the panels.
    case vertical

    public var localizedName: String {
        switch self {
        case .leftToRight: L10n.string("book.direction.ltr")
        case .rightToLeft: L10n.string("book.direction.rtl")
        case .vertical: L10n.string("book.direction.vertical")
        }
    }

    /// For a segmented control, where there is room for a word rather than a sentence.
    public var shortName: String {
        switch self {
        case .leftToRight: L10n.string("book.direction.ltr.short")
        case .rightToLeft: L10n.string("book.direction.rtl.short")
        case .vertical: L10n.string("book.direction.vertical.short")
        }
    }

    /// Two pages side by side only mean something when pages are turned.
    public var supportsSpreads: Bool { self != .vertical }
}
