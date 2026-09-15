import Foundation
import Testing
@testable import GlazeCore

@MainActor
@Suite("What the viewer pinned stays pinned")
struct LibraryFavoriteStoreTests {
    private func store() -> LibraryFavoriteStore {
        LibraryFavoriteStore(
            defaults: UserDefaults(suiteName: "favorites-\(UUID().uuidString)")!,
            storageKey: "library.favorites"
        )
    }

    @Test("Pinning and unpinning are the same gesture")
    func toggles() {
        let store = self.store()
        #expect(store.toggle(sourceKey: "device", kind: .film, itemID: "a.mkv", name: "A") == true)
        #expect(store.contains(sourceKey: "device", kind: .film, itemID: "a.mkv"))
        #expect(store.toggle(sourceKey: "device", kind: .film, itemID: "a.mkv", name: "A") == false)
        #expect(!store.contains(sourceKey: "device", kind: .film, itemID: "a.mkv"))
    }

    /// A film on the NAS and a copy of it on the phone are two different things to
    /// pin, and removing one library must not take the other's stars with it.
    @Test("Two libraries keep their own stars")
    func sourcesAreSeparate() {
        let store = self.store()
        store.toggle(sourceKey: "device", kind: .film, itemID: "a.mkv", name: "A")
        store.toggle(sourceKey: "synology:home", kind: .film, itemID: "a.mkv", name: "A")

        store.removeFavorites(inSource: "device")

        #expect(!store.contains(sourceKey: "device", kind: .film, itemID: "a.mkv"))
        #expect(store.contains(sourceKey: "synology:home", kind: .film, itemID: "a.mkv"))
    }

    @Test("A film and a show with the same name are different pins")
    func kindsAreSeparate() {
        let store = self.store()
        store.toggle(sourceKey: "device", kind: .film, itemID: "bear", name: "The Bear")
        #expect(!store.contains(sourceKey: "device", kind: .series, itemID: "bear"))
    }

    @Test("Pins survive being read back")
    func persists() {
        let defaults = UserDefaults(suiteName: "favorites-\(UUID().uuidString)")!
        let first = LibraryFavoriteStore(defaults: defaults, storageKey: "library.favorites")
        first.toggle(sourceKey: "device.books", kind: .bookCollection, itemID: "원피스", name: "원피스")

        let second = LibraryFavoriteStore(defaults: defaults, storageKey: "library.favorites")
        #expect(second.itemIDs(inSource: "device.books", kind: .bookCollection) == ["원피스"])
    }
}
