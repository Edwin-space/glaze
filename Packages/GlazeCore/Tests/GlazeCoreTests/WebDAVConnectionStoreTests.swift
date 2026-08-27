import Foundation
import Testing
@testable import GlazeCore

@MainActor
struct WebDAVConnectionStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "glaze-webdav-store-tests-\(UUID().uuidString)")!
    }

    @Test func savesAndReloadsConnectionMetadata() {
        let defaults = makeDefaults()
        let connection = WebDAVConnection(
            id: "home-nas",
            name: "Home NAS",
            rootURL: URL(string: "https://nas.local:5006/video")!,
            username: "viewer"
        )

        WebDAVConnectionStore(defaults: defaults).save(connection, password: nil)
        let reloaded = WebDAVConnectionStore(defaults: defaults)

        #expect(reloaded.connections == [connection])
    }

    @Test func editingReplacesTheStableConnectionInsteadOfDuplicatingIt() {
        let defaults = makeDefaults()
        let store = WebDAVConnectionStore(defaults: defaults)
        let original = WebDAVConnection(
            id: "home-nas",
            name: "NAS",
            rootURL: URL(string: "https://nas.local/video")!,
            username: "viewer"
        )
        let edited = WebDAVConnection(
            id: original.id,
            name: "Living Room NAS",
            rootURL: URL(string: "https://nas.local/movies")!,
            username: "viewer"
        )

        store.save(original, password: nil)
        store.save(edited, password: nil)

        #expect(store.connections == [edited])
    }

    @Test func removesPersistedConnectionMetadata() {
        let defaults = makeDefaults()
        let store = WebDAVConnectionStore(defaults: defaults)
        let connection = WebDAVConnection(
            name: "NAS",
            rootURL: URL(string: "https://nas.local/video")!,
            username: ""
        )

        store.save(connection, password: nil)
        store.remove(connection)

        #expect(WebDAVConnectionStore(defaults: defaults).connections.isEmpty)
    }
}
