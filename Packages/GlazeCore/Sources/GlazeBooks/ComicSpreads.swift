import Foundation
import GlazeCore

/// Which pages sit on screen together.
///
/// A comic held sideways shows two pages at once, the way the paper book does. The
/// cover is the exception: it was printed on its own, so pairing it with page two
/// puts every spread after it one page out of step — the mistake that makes a
/// double-page illustration break across the fold.
public struct ComicSpreads: Equatable, Sendable {
    public let pageCount: Int
    public let isDouble: Bool

    public init(pageCount: Int, isDouble: Bool) {
        self.pageCount = max(0, pageCount)
        self.isDouble = isDouble
    }

    public var count: Int {
        guard pageCount > 0 else { return 0 }
        guard isDouble else { return pageCount }
        // The cover, then the rest two at a time.
        return 1 + (pageCount - 1 + 1) / 2
    }

    /// The page numbers on the given spread, in left-to-right order.
    public func pages(at index: Int) -> [Int] {
        guard index >= 0, index < count else { return [] }
        guard isDouble else { return [index] }
        guard index > 0 else { return [0] }

        let first = (index - 1) * 2 + 1
        let second = first + 1
        return second < pageCount ? [first, second] : [first]
    }

    public func index(containing page: Int) -> Int {
        guard isDouble else { return min(max(0, page), max(0, pageCount - 1)) }
        guard page > 0 else { return 0 }
        return (page - 1) / 2 + 1
    }
}
