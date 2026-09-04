import Foundation
import Testing
@testable import GlazeCore

/// Answers requests from memory so the loader can be exercised without a NAS.
final class StubSubtitleProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var statusCode: Int = 200
        var body: Data = Data()
        /// Lets a server lie about its size, the way a misidentified file would.
        var declaredLength: Int?
    }

    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var response = Response()
    nonisolated(unsafe) private static var receivedAuthorization: [String?] = []
    nonisolated(unsafe) private static var requestCount = 0

    static func reset(_ response: Response) {
        lock.lock()
        defer { lock.unlock() }
        self.response = response
        receivedAuthorization = []
        requestCount = 0
    }

    static var authorizationHeaders: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return receivedAuthorization
    }

    static var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let response = Self.response
        Self.receivedAuthorization.append(request.value(forHTTPHeaderField: "Authorization"))
        Self.requestCount += 1
        Self.lock.unlock()

        let length = response.declaredLength ?? response.body.count
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(length)]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct NetworkSubtitleLoaderTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubSubtitleProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeCacheDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glaze-subtitle-loader-\(UUID().uuidString)", isDirectory: true)
        return url
    }

    private static let srtBody = Data("""
    1
    00:00:01,000 --> 00:00:03,000
    Hello

    """.utf8)

    @Test func downloadsASidecarAndCachesIt() async throws {
        StubSubtitleProtocol.reset(.init(body: Self.srtBody))
        let cache = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let loader = NetworkSubtitleLoader(session: makeSession(), cacheDirectory: cache)
        let resource = NetworkSubtitleResource(
            url: URL(string: "http://nas.local/Film.ko.srt")!,
            displayName: "Film.ko.srt",
            languageCode: "ko"
        )

        let first = try await loader.load(resource)
        #expect(try String(contentsOf: first, encoding: .utf8).contains("Hello"))

        // A second request for the same subtitle must come from disk, not the NAS.
        let second = try await loader.load(resource)
        #expect(first == second)
        #expect(StubSubtitleProtocol.callCount == 1)
    }

    /// The password reaches the loader percent-encoded inside the URL, because that is
    /// the form VLC is handed. It has to arrive at the server decoded.
    @Test func sendsCredentialsAsAHeaderRatherThanInTheURL() async throws {
        StubSubtitleProtocol.reset(.init(body: Self.srtBody))
        let cache = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        var components = URLComponents(string: "http://nas.local/Film.ko.srt")!
        components.user = "glaze"
        components.password = "p@ss w/ord"
        #expect(components.url!.absoluteString.contains("p%40ss%20w%2Ford"))

        let loader = NetworkSubtitleLoader(session: makeSession(), cacheDirectory: cache)
        _ = try await loader.load(
            NetworkSubtitleResource(url: components.url!, displayName: "Film.ko.srt")
        )

        let expected = "Basic " + Data("glaze:p@ss w/ord".utf8).base64EncodedString()
        #expect(StubSubtitleProtocol.authorizationHeaders == [expected])
    }

    @Test func refusesAServerErrorInsteadOfCachingIt() async throws {
        StubSubtitleProtocol.reset(.init(statusCode: 401, body: Data("denied".utf8)))
        let cache = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let loader = NetworkSubtitleLoader(session: makeSession(), cacheDirectory: cache)
        await #expect(throws: NetworkSubtitleLoader.LoaderError.httpStatus(401)) {
            try await loader.load(
                NetworkSubtitleResource(
                    url: URL(string: "http://nas.local/Film.ko.srt")!,
                    displayName: "Film.ko.srt"
                )
            )
        }
    }

    @Test func refusesAFileLargerThanASubtitleCouldBe() async throws {
        StubSubtitleProtocol.reset(.init(body: Data(repeating: 0x20, count: 4_096)))
        let cache = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let loader = NetworkSubtitleLoader(
            session: makeSession(),
            cacheDirectory: cache,
            maximumBytes: 1_024
        )
        await #expect(throws: NetworkSubtitleLoader.LoaderError.responseTooLarge) {
            try await loader.load(
                NetworkSubtitleResource(
                    url: URL(string: "http://nas.local/Film.ko.srt")!,
                    displayName: "Film.ko.srt"
                )
            )
        }
    }

    /// A server that understates its length must not get past the cap either.
    @Test func refusesAnOversizedBodyThatWasDeclaredSmall() async throws {
        StubSubtitleProtocol.reset(
            .init(body: Data(repeating: 0x20, count: 4_096), declaredLength: 10)
        )
        let cache = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let loader = NetworkSubtitleLoader(
            session: makeSession(),
            cacheDirectory: cache,
            maximumBytes: 1_024
        )
        await #expect(throws: NetworkSubtitleLoader.LoaderError.responseTooLarge) {
            try await loader.load(
                NetworkSubtitleResource(
                    url: URL(string: "http://nas.local/Film.ko.srt")!,
                    displayName: "Film.ko.srt"
                )
            )
        }
    }

    @Test func convertsAnASSSidecarThroughTheInjectedConverter() async throws {
        StubSubtitleProtocol.reset(.init(body: Data("[Events]\n".utf8)))
        let cache = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let loader = NetworkSubtitleLoader(
            session: makeSession(),
            convertToSRT: { _, destination in
                try Data("converted".utf8).write(to: destination)
            },
            cacheDirectory: cache
        )
        let localURL = try await loader.load(
            NetworkSubtitleResource(
                url: URL(string: "http://nas.local/Film.ja.ass")!,
                displayName: "Film.ja.ass",
                languageCode: "ja"
            )
        )

        #expect(localURL.pathExtension == "srt")
        #expect(try String(contentsOf: localURL, encoding: .utf8) == "converted")
    }

    /// Apple TV has no ffmpeg. Rather than caching a file the parser cannot read, the
    /// loader says so.
    @Test func reportsWhenNoConverterCanHandleAnASSSidecar() async throws {
        StubSubtitleProtocol.reset(.init(body: Data("[Events]\n".utf8)))
        let cache = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let loader = NetworkSubtitleLoader(session: makeSession(), cacheDirectory: cache)
        await #expect(throws: NetworkSubtitleLoader.LoaderError.conversionUnavailable) {
            try await loader.load(
                NetworkSubtitleResource(
                    url: URL(string: "http://nas.local/Film.ja.ass")!,
                    displayName: "Film.ja.ass"
                )
            )
        }
        #expect(StubSubtitleProtocol.callCount == 0)
    }
}
