import Foundation
import Testing
@testable import GlazeCore

@MainActor
struct WebDAVFavoriteStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "glaze-webdav-favorite-tests-\(UUID().uuidString)")!
    }

    @Test func togglesAndReloadsAFolderFavorite() {
        let defaults = makeDefaults()
        let url = URL(string: "https://nas.local:5006/video/Movies/")!
        let store = WebDAVFavoriteStore(defaults: defaults)

        store.toggle(connectionID: "home-nas", name: "Movies", url: url)

        let reloaded = WebDAVFavoriteStore(defaults: defaults)
        #expect(reloaded.favorites.count == 1)
        #expect(reloaded.favorites[0].connectionID == "home-nas")
        #expect(reloaded.contains(connectionID: "home-nas", url: url))
    }

    @Test func treatsTrailingSlashAsTheSameFolder() {
        let store = WebDAVFavoriteStore(defaults: makeDefaults())
        let withSlash = URL(string: "https://nas.local/video/Movies/")!
        let withoutSlash = URL(string: "https://nas.local/video/Movies")!

        store.toggle(connectionID: "home-nas", name: "Movies", url: withSlash)
        store.toggle(connectionID: "home-nas", name: "Movies", url: withoutSlash)

        #expect(store.favorites.isEmpty)
    }

    @Test func removingAConnectionClearsOnlyItsFavorites() {
        let store = WebDAVFavoriteStore(defaults: makeDefaults())
        store.toggle(
            connectionID: "home-nas",
            name: "Movies",
            url: URL(string: "https://home.local/video/Movies/")!
        )
        store.toggle(
            connectionID: "office-nas",
            name: "Review",
            url: URL(string: "https://office.local/video/Review/")!
        )

        store.removeFavorites(forConnectionID: "home-nas")

        #expect(store.favorites.map(\.connectionID) == ["office-nas"])
    }
}
