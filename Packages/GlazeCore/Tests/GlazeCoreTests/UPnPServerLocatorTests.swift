import Foundation
import GlazeCore
import Testing

/// Against a real DLNA server run beside the tests: `scratchpad/dlnaserver.py`.
/// Skipped when it is not running, so the suite still passes on a machine without it.
@Suite("Finding a DLNA server by address, without multicast")
struct UPnPServerLocatorTests {
    static let testServer = URL(string: "http://127.0.0.1:8201/rootDesc.xml")!

    static var isServerRunning: Bool {
        var running = false
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: testServer) { _, response, _ in
            running = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return running
    }

    @Test("A pasted description address is used as it is")
    func locatesFromADescriptionURL() async throws {
        try await confirmServerIsRunning()
        let server = try await UPnPServerLocator().locate(Self.testServer.absoluteString)
        #expect(server.friendlyName == "Test DLNA Server")
        #expect(server.contentDirectoryControlURL.path == "/ctl/ContentDir")
    }

    @Test("A host and port with no path finds the description anyway")
    func locatesFromHostAndPort() async throws {
        try await confirmServerIsRunning()
        let server = try await UPnPServerLocator().locate("127.0.0.1:8201")
        #expect(server.friendlyName == "Test DLNA Server")
    }

    @Test("The server that was found can be browsed")
    func browsesWhatItFound() async throws {
        try await confirmServerIsRunning()
        let server = try await UPnPServerLocator().locate(Self.testServer.absoluteString)
        let nodes = try await UPnPContentDirectoryClient().browse(server: server, objectID: "0")
        #expect(nodes.count == 1)
        #expect(nodes.first?.title == "Video")
    }

    @Test("An address nothing answers on is a failure, not an empty list")
    func reportsWhenNothingAnswers() async throws {
        await #expect(throws: UPnPServerLocator.LocatorError.notFound) {
            try await UPnPServerLocator(responseWait: 1).locate("127.0.0.1:9")
        }
    }

    /// The path that matters on an Apple TV: one question to one host, no multicast.
    @Test("A unicast search asks the one server and gets its description address")
    func asksOneServerDirectly() async throws {
        try await confirmServerIsRunning()
        let answered = try await UPnPMediaServerDiscoveryService(responseWait: 2)
            .askServer(host: "127.0.0.1", port: 1901)
        #expect(answered.first?.friendlyName == "Test DLNA Server")
        #expect(answered.first?.descriptionURL == Self.testServer)
    }

    @Test("Blank text is not an address")
    func rejectsEmptyText() async throws {
        await #expect(throws: UPnPServerLocator.LocatorError.noAddress) {
            try await UPnPServerLocator().locate("   ")
        }
    }

    private func confirmServerIsRunning() async throws {
        try #require(Self.isServerRunning, "the test DLNA server is not running")
    }
}

@Suite("Walking a DLNA server folder by folder")
struct DLNAFolderReadingTests {
    @Test("The root lists folders, and a folder lists its films")
    func readsFoldersAndFilms() async throws {
        try #require(UPnPServerLocatorTests.isServerRunning, "the test DLNA server is not running")
        let server = try await UPnPServerLocator()
            .locate(UPnPServerLocatorTests.testServer.absoluteString)
        let reader = NetworkFolderReader(
            serverName: server.friendlyName,
            backend: .dlna(server: server),
            rootPath: "0"
        )

        let root = try await reader.read("")
        #expect(root.count == 1)
        #expect(root.first?.isFolder == true)

        let folder = try #require(root.first)
        let films = try await reader.read(folder.path)
        #expect(films.count == 1)
        let film = try #require(films.first)
        guard case .film(let resource, _) = film.kind else {
            Issue.record("a video item should read back as a film")
            return
        }
        #expect(resource.playbackURL.absoluteString.hasSuffix("/media/testmedia.mkv"))
        #expect(film.displayName == "Testmedia")
    }
}

@Suite("Building the shelves from a DLNA server", .serialized)
@MainActor
struct DLNAHomeCatalogTests {
    /// What the television's Home shelves are built from. A server whose films sit
    /// inside a folder — which is every server — has to be walked, not just listed.
    @Test("Selecting a server catalogues the films inside its folders")
    func catalogsFilmsBelowTheRoot() async throws {
        try #require(UPnPServerLocatorTests.isServerRunning, "the test DLNA server is not running")
        let server = try await UPnPServerLocator()
            .locate(UPnPServerLocatorTests.testServer.absoluteString)

        let model = NetworkMediaBrowserModel()
        model.add(server)
        await model.select(server)

        #expect(model.errorMessage == nil)
        #expect(model.homeNodes.count == 1)
        #expect(model.homeNodes.first?.title == "Testmedia")

        // What the television then puts on its shelves.
        let items = model.homeNodes.compactMap { node -> MediaLibraryItem? in
            guard case .video(let resource) = node.kind else { return nil }
            return MediaLibraryItem(
                id: node.id,
                sourceName: node.title,
                parsed: MediaTitleParser.parse(node.title),
                playbackURL: resource.playbackURL
            )
        }
        let library = MediaLibraryIndex.build(from: items)
        #expect(library.movies.count + library.series.count == 1)
    }
}
