import Foundation
import Testing
@testable import GlazeCore

/// Captures PUTs so what would land on a NAS can be checked without one.
final class StubUploadProtocol: URLProtocol, @unchecked Sendable {
    struct Upload: Equatable, Sendable {
        let path: String
        let authorization: String?
        let body: Data
    }

    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var uploads: [Upload] = []
    nonisolated(unsafe) private static var status = 201

    static func reset(status: Int = 201) {
        lock.lock()
        defer { lock.unlock() }
        uploads = []
        self.status = status
    }

    static var received: [Upload] {
        lock.lock()
        defer { lock.unlock() }
        return uploads
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    /// URLSession moves a body set on the request into a stream, so it has to be read
    /// back out rather than taken from `httpBody`.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(contentsOf: buffer[0..<read])
            }
            stream.close()
        }

        Self.lock.lock()
        Self.uploads.append(
            Upload(
                path: request.url?.path ?? "",
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                body: body
            )
        )
        let status = Self.status
        Self.lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct SidecarDestinationTests {
    private func makeClient() -> WebDAVClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubUploadProtocol.self]
        return WebDAVClient(session: URLSession(configuration: configuration))
    }

    private let match = MediaMetadataMatch(
        providerID: "tmdb",
        title: "기생충",
        originalTitle: "Parasite",
        year: 2019,
        overview: "반지하의 가족.",
        genres: ["스릴러"],
        externalIDs: MediaExternalIDs(imdbID: "tt6751668", tmdbID: "496243")
    )

    /// The gap this closes: a film on a NAS could not be described at all, because the
    /// only writer needed a local path.
    @Test func writesTheNFOAndPosterBesideAFilmOnANAS() async throws {
        StubUploadProtocol.reset()
        let destination = WebDAVSidecarDestination(
            besideVideoAt: URL(string: "https://nas.local:5006/Movies/Parasite/Parasite.2019.mkv")!,
            credentials: (username: "glaze", password: "secret"),
            client: makeClient()
        )

        let written = try await MediaSidecarWriter().write(
            match,
            poster: Data("jpeg".utf8),
            baseName: "Parasite.2019",
            to: destination
        )

        #expect(written == ["Parasite.2019.nfo", "Parasite.2019-poster.jpg"])
        let uploads = StubUploadProtocol.received
        #expect(uploads.map(\.path) == [
            "/Movies/Parasite/Parasite.2019.nfo",
            "/Movies/Parasite/Parasite.2019-poster.jpg"
        ])
        let nfo = try #require(String(data: uploads[0].body, encoding: .utf8))
        #expect(nfo.contains("<title>기생충</title>"))
        #expect(nfo.contains("<year>2019</year>"))
        #expect(uploads[1].body == Data("jpeg".utf8))
    }

    @Test func sendsTheShareCredentialsWithEachWrite() async throws {
        StubUploadProtocol.reset()
        let destination = WebDAVSidecarDestination(
            folderURL: URL(string: "https://nas.local:5006/Movies")!,
            credentials: (username: "glaze", password: "p@ss word"),
            client: makeClient()
        )
        try await destination.write(Data("x".utf8), named: "a.nfo")

        let expected = "Basic " + Data("glaze:p@ss word".utf8).base64EncodedString()
        #expect(StubUploadProtocol.received.first?.authorization == expected)
    }

    /// A poster that will not upload must not lose the .nfo that already did.
    @Test func keepsTheNFOWhenThePosterCannotBeWritten() async throws {
        StubUploadProtocol.reset(status: 507)
        let destination = WebDAVSidecarDestination(
            folderURL: URL(string: "https://nas.local:5006/Movies")!,
            credentials: nil,
            client: makeClient()
        )
        await #expect(throws: MediaSidecarWriter.WriteError.writeFailed) {
            try await MediaSidecarWriter().write(
                match, poster: Data("jpeg".utf8), baseName: "A", to: destination
            )
        }
    }

    @Test func writesBesideAFilmOnDiskThroughTheSameWriter() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glaze-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let videoURL = folder.appendingPathComponent("Parasite.2019.mkv")
        try Data("video".utf8).write(to: videoURL)

        let written = try await MediaSidecarWriter().write(
            match,
            poster: Data("jpeg".utf8),
            baseName: "Parasite.2019",
            to: LocalSidecarDestination(videoURL: videoURL)
        )

        #expect(written == ["Parasite.2019.nfo", "Parasite.2019-poster.jpg"])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Parasite.2019.nfo").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Parasite.2019-poster.jpg").path))
    }
}
