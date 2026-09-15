import Foundation
import GlazeCore

/// How one particular book should be read.
///
/// Kept per book rather than once for the app, because a shelf holds both kinds:
/// a Korean manga scan opens right to left, and the PDF manual next to it does not.
/// A single setting would have the viewer changing it every time they swapped books.
public struct ReadingOptionsStore {
    private let defaults: UserDefaults
    private let directionKey = "reading.directions"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// - Parameter fallback: what the app is set to, used until this book is told
    ///   otherwise.
    public func direction(for bookID: String, fallback: ReadingDirection) -> ReadingDirection {
        guard let stored = directions()[bookID], let direction = ReadingDirection(rawValue: stored) else {
            return fallback
        }
        return direction
    }

    public func setDirection(_ direction: ReadingDirection, for bookID: String) {
        var all = directions()
        all[bookID] = direction.rawValue
        defaults.set(all, forKey: directionKey)
    }

    /// How far into a chapter the reader had got, as a fraction of its height.
    ///
    /// A book's chapter can be an hour of reading, so remembering only which chapter
    /// would drop someone back at its first sentence every time.
    public func scrollOffset(for bookID: String, chapter: Int) -> Double {
        offsets()[Self.key(bookID, chapter)] ?? 0
    }

    public func setScrollOffset(_ offset: Double, for bookID: String, chapter: Int) {
        var all = offsets()
        let key = Self.key(bookID, chapter)
        let rounded = (min(max(0, offset), 1) * 1_000).rounded() / 1_000
        guard all[key] != rounded else { return }
        all[key] = rounded
        defaults.set(all, forKey: offsetKey)
    }

    private static func key(_ bookID: String, _ chapter: Int) -> String { "\(bookID)#\(chapter)" }

    private var offsetKey: String { "reading.offsets" }

    private func offsets() -> [String: Double] {
        defaults.dictionary(forKey: offsetKey) as? [String: Double] ?? [:]
    }

    private func directions() -> [String: String] {
        defaults.dictionary(forKey: directionKey) as? [String: String] ?? [:]
    }
}
