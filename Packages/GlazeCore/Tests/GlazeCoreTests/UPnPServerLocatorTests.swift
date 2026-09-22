import Foundation
import GlazeCore
import Testing

/// The DLNA server these tests run against: `docs/47` says how it is started.
///
/// Kept outside the suites it gates — a suite whose trait reads its own static is a
/// circular reference — and treated as absent rather than broken when nothing answers,
/// so a machine without the test server still runs a clean suite.
enum DLNATestServer {
    static let descriptionURL = URL(string: "http://127.0.0.1:8201/rootDesc.xml")!

    static var isRunning: Bool {
        var running = false
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: descriptionURL) { _, response, _ in
            running = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return running
    }
}

@Suite(
    "Finding a DLNA server by address, without multicast",
    .enabled(if: DLNATestServer.isRunning)
)
struct UPnPServerLocatorTests {
    @Test("A pasted description address is used as it is")
    func locatesFromADescriptionURL() async throws {
        let server = try await UPnPServerLocator().locate(DLNATestServer.descriptionURL.absoluteString)
        #expect(server.friendlyName == "Test DLNA Server")
        #expect(server.contentDirectoryControlURL.path == "/ctl/ContentDir")
    }

    @Test("A host and port with no path finds the description anyway")
    func locatesFromHostAndPort() async throws {
        let server = try await UPnPServerLocator().locate("127.0.0.1:8201")
        #expect(server.friendlyName == "Test DLNA Server")
    }

    @Test("The server that was found can be browsed")
    func browsesWhatItFound() async throws {
        let server = try await UPnPServerLocator().locate(DLNATestServer.descriptionURL.absoluteString)
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
        let answered = try await UPnPMediaServerDiscoveryService(responseWait: 2)
            .askServer(host: "127.0.0.1", port: 1901)
        #expect(answered.first?.friendlyName == "Test DLNA Server")
        #expect(answered.first?.descriptionURL == DLNATestServer.descriptionURL)
    }

    @Test("Blank text is not an address")
    func rejectsEmptyText() async throws {
        await #expect(throws: UPnPServerLocator.LocatorError.noAddress) {
            try await UPnPServerLocator().locate("   ")
        }
    }
}

@Suite(
    "Walking a DLNA server folder by folder",
    .enabled(if: DLNATestServer.isRunning)
)
struct DLNAFolderReadingTests {
    @Test("The root lists folders, and a folder lists its films")
    func readsFoldersAndFilms() async throws {
        let server = try await UPnPServerLocator()
            .locate(DLNATestServer.descriptionURL.absoluteString)
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

@Suite(
    "Building the shelves from a DLNA server",
    .serialized,
    .enabled(if: DLNATestServer.isRunning)
)
@MainActor
struct DLNAHomeCatalogTests {
    /// What the television's Home shelves are built from. A server whose films sit
    /// inside a folder — which is every server — has to be walked, not just listed.
    @Test("Selecting a server catalogues the films inside its folders")
    func catalogsFilmsBelowTheRoot() async throws {
        let server = try await UPnPServerLocator()
            .locate(DLNATestServer.descriptionURL.absoluteString)

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
