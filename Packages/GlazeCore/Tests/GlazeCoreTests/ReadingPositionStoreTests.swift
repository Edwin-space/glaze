import Foundation
import Testing
@testable import GlazeBooks
@testable import GlazeCore

@Suite("A book remembers the page it was left on")
struct ReadingPositionStoreTests {
    private func store() -> (ReadingPositionStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "reading-\(UUID().uuidString)")!
        return (ReadingPositionStore(defaults: defaults), defaults)
    }

    @Test("The page comes back")
    func remembers() {
        let (store, _) = self.store()
        store.record(page: 40, of: 200, for: "원피스 01권.cbz")
        #expect(store.page(for: "원피스 01권.cbz") == 40)
    }

    /// Opening the cover and closing again is not reading. Storing that would put the
    /// book on the "reading" shelf for a tap that never went anywhere.
    @Test("Page one is not a place to resume from")
    func ignoresTheCover() {
        let (store, _) = self.store()
        store.record(page: 0, of: 200, for: "book")
        #expect(store.page(for: "book") == nil)
    }

    /// The failure this guards against: reopening a book you finished and landing on
    /// the last page instead of the first.
    @Test("A finished book is forgotten rather than stored")
    func forgetsWhenFinished() {
        let (store, _) = self.store()
        store.record(page: 40, of: 200, for: "book")
        store.record(page: 199, of: 200, for: "book")
        #expect(store.page(for: "book") == nil)
    }

    @Test("Progress needs a page count, which is written down when the book is opened")
    func progress() {
        let (store, _) = self.store()
        store.rememberPageCount(200, for: "book")
        store.record(page: 99, of: 200, for: "book")
        #expect(store.pageCount(for: "book") == 200)
        #expect(store.progress(for: "book", pageCount: 200) == 0.5)
    }
}

@MainActor
@Suite("The shelf notices when a book is put down")
struct ReadingProgressStoreTests {
    /// The failure this guards against: closing a comic on page three wrote the page
    /// to `UserDefaults`, which nothing watches, so the shelf carried on showing no
    /// progress at all until the screen happened to be rebuilt.
    @Test("Recording a page updates what the shelves read")
    func publishes() {
        let defaults = UserDefaults(suiteName: "reading-progress-\(UUID().uuidString)")!
        let progress = ReadingProgressStore(store: ReadingPositionStore(defaults: defaults))

        #expect(progress.progress(for: "book") == nil)
        progress.record(page: 49, of: 100, for: "book")
        #expect(progress.page(for: "book") == 49)
        #expect(progress.progress(for: "book") == 0.5)
    }

    @Test("Finishing a book clears it from the shelves too")
    func clearsWhenFinished() {
        let defaults = UserDefaults(suiteName: "reading-progress-\(UUID().uuidString)")!
        let progress = ReadingProgressStore(store: ReadingPositionStore(defaults: defaults))

        progress.record(page: 49, of: 100, for: "book")
        progress.record(page: 99, of: 100, for: "book")
        #expect(progress.page(for: "book") == nil)
    }
}
