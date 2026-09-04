import Foundation
import Testing
@testable import GlazeCore

/// A NAS made of canned PROPFIND answers, so the walk can be checked without one.
final class StubWebDAVProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var folders: [String: [(name: String, isDirectory: Bool)]] = [:]
    nonisolated(unsafe) private static var files: [String: Data] = [:]
    nonisolated(unsafe) private static var listedPaths: [String] = []

    static func reset(
        folders: [String: [(name: String, isDirectory: Bool)]],
        files: [String: Data] = [:]
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.folders = folders
        self.files = files
        listedPaths = []
    }

    static var listed: [String] {
        lock.lock()
        defer { lock.unlock() }
        return listedPaths
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path

        if request.httpMethod == "PROPFIND" {
            Self.lock.lock()
            let children = Self.folders[path]
            if children != nil { Self.listedPaths.append(path) }
            Self.lock.unlock()

            guard let children else { return finish(status: 404, body: Data()) }
            var xml = "<?xml version=\"1.0\"?><D:multistatus xmlns:D=\"DAV:\">"
            xml += response(href: path, name: url.lastPathComponent, isDirectory: true)
            for child in children {
                let childPath = path.hasSuffix("/") ? path + child.name : path + "/" + child.name
                xml += response(href: childPath, name: child.name, isDirectory: child.isDirectory)
            }
            xml += "</D:multistatus>"
            return finish(status: 207, body: Data(xml.utf8))
        }

        Self.lock.lock()
        let body = Self.files[path]
        Self.lock.unlock()
        finish(status: body == nil ? 404 : 200, body: body ?? Data())
    }

    private func response(href: String, name: String, isDirectory: Bool) -> String {
        let resourceType = isDirectory ? "<D:collection/>" : ""
        return """
        <D:response><D:href>\(href)</D:href><D:propstat><D:prop>
        <D:displayname>\(name)</D:displayname>
        <D:resourcetype>\(resourceType)</D:resourcetype>
        <D:getlastmodified>Wed, 01 Jan 2025 00:00:00 GMT</D:getlastmodified>
        </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
        """
    }

    private func finish(status: Int, body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct WebDAVLibraryLoaderTests {
    private func makeLoader(limits: WebDAVLibraryLoader.Limits = .init()) -> WebDAVLibraryLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubWebDAVProtocol.self]
        return WebDAVLibraryLoader(
            client: WebDAVClient(session: URLSession(configuration: configuration)),
            limits: limits
        )
    }

    private let root = URL(string: "http://nas.local/media")!

    /// The shape people actually keep: films in their own folders, a show split by
    /// season. A loader that listed only the address it was given finds nothing here.
    @Test func walksIntoSubfoldersInsteadOfStoppingAtTheTopLevel() async throws {
        StubWebDAVProtocol.reset(folders: [
            "/media": [("Movies", true), ("TV", true)],
            "/media/Movies": [("Parasite (2019)", true)],
            "/media/Movies/Parasite (2019)": [
                ("Parasite.2019.1080p.mkv", false),
                ("Parasite.2019.1080p-poster.jpg", false)
            ],
            "/media/TV": [("The Bear", true)],
            "/media/TV/The Bear": [("Season 01", true)],
            "/media/TV/The Bear/Season 01": [
                ("The.Bear.S01E01.mkv", false),
                ("The.Bear.S01E02.mkv", false)
            ]
        ])

        let library = try await makeLoader().load(root: root, credentials: nil)

        #expect(library.movies.count == 1)
        #expect(library.movies[0].displayTitle == "Parasite")
        #expect(library.movies[0].posterURL?.lastPathComponent == "Parasite.2019.1080p-poster.jpg")
        #expect(library.series.count == 1)
        #expect(library.series[0].episodeCount == 2)
    }

    @Test func readsTheNFOSittingBesideAFilm() async throws {
        let nfo = """
        <movie><title>기생충</title><year>2019</year><genre>스릴러</genre>
        <plot>반지하의 가족.</plot></movie>
        """
        StubWebDAVProtocol.reset(
            folders: ["/media": [("Parasite.2019.mkv", false), ("Parasite.2019.nfo", false)]],
            files: ["/media/Parasite.2019.nfo": Data(nfo.utf8)]
        )

        let library = try await makeLoader().load(root: root, credentials: nil)
        let movie = try #require(library.movies.first)
        #expect(movie.displayTitle == "기생충")
        #expect(movie.plot == "반지하의 가족.")
        #expect(library.genres.map(\.name) == ["스릴러"])
    }

    @Test func stopsWalkingAtTheDepthItWasGiven() async throws {
        StubWebDAVProtocol.reset(folders: [
            "/media": [("A", true)],
            "/media/A": [("B", true)],
            "/media/A/B": [("Deep.2020.mkv", false)]
        ])

        let library = try await makeLoader(limits: .init(depth: 1, folders: 250))
            .load(root: root, credentials: nil)
        #expect(library.isEmpty)
        #expect(StubWebDAVProtocol.listed == ["/media", "/media/A"])
    }

    /// A share with more folders than the ceiling must return what it read, not fail.
    @Test func stopsAfterTheFolderCeilingRatherThanCrawlingTheWholeNAS() async throws {
        var folders: [String: [(name: String, isDirectory: Bool)]] = [:]
        folders["/media"] = (0..<50).map { ("F\($0)", true) }
        for index in 0..<50 {
            folders["/media/F\(index)"] = [("Film\(index).2020.mkv", false)]
        }
        StubWebDAVProtocol.reset(folders: folders)

        let library = try await makeLoader(limits: .init(depth: 3, folders: 5))
            .load(root: root, credentials: nil)
        #expect(StubWebDAVProtocol.listed.count == 5)
        #expect(library.movies.count == 4)
    }

    /// One folder the server refuses must not lose the films in the others.
    @Test func keepsGoingPastAFolderItCannotRead() async throws {
        StubWebDAVProtocol.reset(folders: [
            "/media": [("Broken", true), ("Good", true)],
            "/media/Good": [("Film.2020.mkv", false)]
        ])

        let library = try await makeLoader().load(root: root, credentials: nil)
        #expect(library.movies.count == 1)
    }


    /// A Synology share root lists the shared folders, so a film is two levels down
    /// before the library begins, and a series adds a season folder on top.
    @Test func reachesAFilmInASynologyShapedShare() async throws {
        StubWebDAVProtocol.reset(folders: [
            "/": [("video", true)],
            "/video": [("Media", true)],
            "/video/Media": [("Parasite (2019)", true), ("The Bear", true)],
            "/video/Media/Parasite (2019)": [("Parasite.2019.1080p.mkv", false)],
            "/video/Media/The Bear": [("Season 01", true)],
            "/video/Media/The Bear/Season 01": [("The.Bear.S01E01.1080p.mkv", false)]
        ])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubWebDAVProtocol.self]
        let loader = WebDAVLibraryLoader(
            client: WebDAVClient(session: URLSession(configuration: configuration))
        )

        let library = try await loader.load(root: URL(string: "https://nas.local:5006/")!, credentials: nil)
        #expect(library.movies.count == 1)
        #expect(library.series.first?.episodeCount == 1)
    }

    @Test func reportsProgressSoALargeShareCanSaySomethingTrue() async throws {
        StubWebDAVProtocol.reset(folders: [
            "/media": [("A", true), ("B", true)],
            "/media/A": [("One.2020.mkv", false)],
            "/media/B": [("Two.2021.mkv", false)]
        ])

        let counts = LockedCounts()
        _ = try await makeLoader().load(root: root, credentials: nil) { counts.append($0) }
        #expect(counts.values == [1, 2, 3])
    }
}

final class LockedCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    func append(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite struct WebDAVTransportErrorTests {
    /// Reaching a NAS by IP when its certificate names a domain is an ordinary mistake,
    /// and "could not connect" says nothing about how to fix it.
    @Test func namesACertificateMismatchRatherThanCallingItANetworkFailure() {
        let cases: [URLError.Code] = [
            .secureConnectionFailed,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateHasBadDate,
            .serverCertificateNotYetValid
        ]
        for code in cases {
            #expect(WebDAVError.transport(URLError(code)) == .certificateMismatch)
        }
    }

    @Test func leavesOtherFailuresAsNetworkFailures() {
        guard case .network = WebDAVError.transport(URLError(.timedOut)) else {
            Issue.record("a timeout is a network failure")
            return
        }
        guard case .network = WebDAVError.transport(URLError(.cannotFindHost)) else {
            Issue.record("an unknown host is a network failure")
            return
        }
    }
}
