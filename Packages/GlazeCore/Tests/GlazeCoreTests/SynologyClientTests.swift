import Foundation
import Testing
@testable import GlazeCore

/// A DSM box made of canned answers, so signing in and walking a share can be
/// checked without one.
final class StubSynologyProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var folders: [String: [[String: Any]]] = [:]
    nonisolated(unsafe) private static var loginError: Int?
    nonisolated(unsafe) private static var lastLoginBody: String = ""
    nonisolated(unsafe) private static var listedPaths: [String] = []

    static func reset(folders: [String: [[String: Any]]] = [:], loginError: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        self.folders = folders
        self.loginError = loginError
        lastLoginBody = ""
        listedPaths = []
    }

    static var loginBody: String {
        lock.lock(); defer { lock.unlock() }
        return lastLoginBody
    }

    static var listed: [String] {
        lock.lock(); defer { lock.unlock() }
        return listedPaths
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        if url.path.hasSuffix("auth.cgi") {
            var body = ""
            if let data = request.httpBody {
                body = String(decoding: data, as: UTF8.self)
            } else if let stream = request.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 4096)
                let read = stream.read(&buffer, maxLength: buffer.count)
                stream.close()
                body = String(decoding: buffer.prefix(max(read, 0)), as: UTF8.self)
            }
            Self.lock.lock()
            Self.lastLoginBody = body
            let error = Self.loginError
            Self.lock.unlock()

            if let error {
                return finish(["success": false, "error": ["code": error]])
            }
            return finish(["success": true, "data": ["sid": "session-token"]])
        }

        switch value("method") {
        case "list_share":
            return finish(["success": true, "data": ["shares": [
                ["path": "/video", "name": "video", "isdir": true]
            ]]])
        case "list":
            let path = value("folder_path") ?? ""
            Self.lock.lock()
            let files = Self.folders[path]
            if files != nil { Self.listedPaths.append(path) }
            Self.lock.unlock()
            guard let files else { return finish(["success": false, "error": ["code": 408]]) }
            return finish(["success": true, "data": ["files": files]])
        case "download":
            return finishData(Data("<movie><title>기생충</title></movie>".utf8))
        default:
            return finish(["success": false, "error": ["code": 101]])
        }
    }

    override func stopLoading() {}

    private func finish(_ payload: [String: Any]) {
        finishData(try! JSONSerialization.data(withJSONObject: payload))
    }

    private func finishData(_ data: Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Reaching a Synology the way DS File does", .serialized)
struct SynologyClientTests {
    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubSynologyProtocol.self]
        return URLSession(configuration: configuration)
    }

    private let base = URL(string: "https://nas.example.com:5001")!

    private func file(_ name: String, size: Int64 = 1_000) -> [String: Any] {
        ["path": "/video/\(name)", "name": name, "isdir": false,
         "additional": ["size": NSNumber(value: size)]]
    }

    @Test("Signs in and keeps the session token")
    func signsIn() async throws {
        StubSynologyProtocol.reset()
        let signedIn = try await SynologyClient(session: session)
            .logIn(to: base, account: "someone", password: "secret")
        #expect(signedIn.sid == "session-token")
    }

    @Test("Never puts the password in the address")
    func passwordStaysOutOfTheURL() async throws {
        StubSynologyProtocol.reset()
        _ = try await SynologyClient(session: session)
            .logIn(to: base, account: "someone", password: "secret")
        // A password in a query string ends up in proxy logs and crash reports.
        #expect(StubSynologyProtocol.loginBody.contains("passwd=secret"))
    }

    @Test("Says plainly when two-factor is switched on")
    func asksForTheCode() async throws {
        StubSynologyProtocol.reset(loginError: 403)
        await #expect(throws: SynologyError.needsOneTimeCode) {
            _ = try await SynologyClient(session: session)
                .logIn(to: base, account: "someone", password: "secret")
        }
    }

    @Test("Tells a wrong password apart from a rejected code")
    func separatesTheFailures() async throws {
        StubSynologyProtocol.reset(loginError: 400)
        await #expect(throws: SynologyError.badCredentials) {
            _ = try await SynologyClient(session: session)
                .logIn(to: base, account: "someone", password: "wrong")
        }
        StubSynologyProtocol.reset(loginError: 404)
        await #expect(throws: SynologyError.oneTimeCodeRejected) {
            _ = try await SynologyClient(session: session)
                .logIn(to: base, account: "someone", password: "secret", oneTimeCode: "000000")
        }
    }

    @Test("Reads a share into films with their subtitles")
    func readsAShare() async throws {
        StubSynologyProtocol.reset(folders: [
            "/video": [
                file("Parasite.2019.1080p.mkv"),
                file("Parasite.2019.1080p.ko.srt"),
                file("Parasite.2019.1080p-poster.jpg"),
                ["path": "/video/@eaDir", "name": "@eaDir", "isdir": true]
            ]
        ])
        let client = SynologyClient(session: session)
        let signedIn = try await client.logIn(to: base, account: "someone", password: "secret")
        let library = try await SynologyLibraryLoader(client: client)
            .load(root: "/video", session: signedIn)

        let film = try #require(library.movies.first)
        #expect(library.movies.count == 1)
        #expect(film.subtitleURLs.count == 1)
        #expect(film.posterURL != nil)
        // Synology's own thumbnail folder is not part of anyone's library.
        #expect(!StubSynologyProtocol.listed.contains { $0.contains("@eaDir") })
    }

    @Test("Hands the player an address it can seek in")
    func buildsAStreamingAddress() async throws {
        StubSynologyProtocol.reset()
        let client = SynologyClient(session: session)
        let signedIn = try await client.logIn(to: base, account: "someone", password: "secret")
        let url = client.mediaURL(for: "/video/Film.mkv", session: signedIn)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []

        #expect(query.contains { $0.name == "mode" && $0.value == "open" })
        #expect(query.contains { $0.name == "_sid" && $0.value == "session-token" })
        #expect(query.contains { $0.name == "path" && $0.value == "/video/Film.mkv" })
    }
}
