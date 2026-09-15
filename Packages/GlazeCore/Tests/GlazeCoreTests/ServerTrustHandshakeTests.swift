import Foundation
import Testing
@testable import GlazeCore

/// The store's bookkeeping is one thing; refusing and then accepting a real TLS
/// handshake is the thing that either works on a NAS or does not. This stands up a
/// server with a certificate nothing vouches for — exactly what a Synology ships
/// with — and drives the whole path.
@Suite(.serialized)
struct ServerTrustHandshakeTests {
    @Test("A self-signed server is refused, then reachable once its certificate is accepted")
    func refusesThenAccepts() async throws {
        guard let server = try SelfSignedServer.start() else { return }
        defer { server.stop() }

        let store = ServerTrustStore(defaults: UserDefaults(suiteName: "handshake-\(UUID().uuidString)")!)
        let session = URLSession(
            configuration: .ephemeral,
            delegate: ServerTrustDelegate(store: store),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        // Refused, and what it presented is remembered so a screen can offer it.
        await #expect(throws: (any Error).self) { try await session.data(from: server.url) }
        let refused = try #require(store.refused(for: "127.0.0.1"))
        #expect(refused.fingerprint.contains(":"))

        // Accepted by fingerprint — and now the same server answers.
        store.accept(refused)
        let (data, response) = try await session.data(from: server.url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(!data.isEmpty)

        // A different certificate on the same host is still refused.
        store.accept(ServerCertificate(host: "127.0.0.1", fingerprint: "00:11", summary: ""))
        await #expect(throws: (any Error).self) { try await session.data(from: server.url) }
    }
    /// The exact path the app takes: a client refuses, the viewer accepts what it
    /// showed them, and the very next attempt has to get through. This is the step
    /// that was reported as doing nothing.
    @Test("A client that was refused connects after the certificate is accepted")
    func clientRetriesAfterAccepting() async throws {
        guard let server = try SelfSignedServer.start() else { return }
        defer { server.stop() }

        let store = ServerTrustStore.shared
        store.forget(host: "127.0.0.1")
        defer { store.forget(host: "127.0.0.1") }

        let client = SynologyClient()

        // Refused, and the client says why rather than "could not connect".
        var refused: ServerCertificate?
        do {
            _ = try await client.logIn(to: server.url, account: "a", password: "b")
        } catch SynologyError.certificateUntrusted(let certificate) {
            refused = certificate
        } catch {
            Issue.record("expected a certificate refusal, got \(error)")
        }
        let certificate = try #require(refused)

        // Accepted — and the next attempt must reach the server. It is not DSM, so
        // the failure that comes back has to be about *that*, not about TLS.
        store.accept(certificate)
        do {
            _ = try await client.logIn(to: server.url, account: "a", password: "b")
            Issue.record("a plain web server should not have answered as DSM")
        } catch SynologyError.certificateUntrusted {
            Issue.record("still refused after the certificate was accepted")
        } catch {
            // Reached the server and got something that is not DSM. TLS was passed.
        }
    }

    /// The bug this guards against, reported from a real NAS: "trust and connect"
    /// appeared to do nothing. Accepting worked, the next attempt got past TLS and
    /// then failed for its own reason — and because the refusal was still on file,
    /// *that* failure was reported as the same certificate problem and the sheet came
    /// straight back. Forever.
    @Test("Once accepted, a later failure is reported as itself")
    func doesNotBlameTheCertificateForever() async throws {
        guard let server = try SelfSignedServer.start() else { return }

        let store = ServerTrustStore.shared
        store.forget(host: "127.0.0.1")
        defer { store.forget(host: "127.0.0.1") }

        let client = SynologyClient()

        var refused: ServerCertificate?
        do {
            _ = try await client.logIn(to: server.url, account: "a", password: "b")
        } catch SynologyError.certificateUntrusted(let certificate) {
            refused = certificate
        } catch {}
        let certificate = try #require(refused)

        store.accept(certificate)
        // Now make the next attempt fail for a completely different reason.
        server.stop()

        do {
            _ = try await client.logIn(to: server.url, account: "a", password: "b")
            Issue.record("a stopped server should not have answered")
        } catch SynologyError.certificateUntrusted {
            Issue.record("a dead server was blamed on the certificate")
        } catch {
            // Reported as what it is: the server could not be reached.
        }
    }
}

/// A throwaway HTTPS server with a certificate it signed itself.
extension ServerTrustHandshakeTests {
    /// The advice has to be right, not merely helpful-sounding.
    ///
    /// Offering "connect to the name on the certificate" is only the answer when that
    /// name would actually verify. Here the certificate is signed by nobody, so
    /// changing the address would fail exactly the same way — and the viewer must be
    /// shown the fingerprint to judge instead.
    @Test("A name change is not offered when it would not help")
    func doesNotSuggestANameThatWouldAlsoFail() async throws {
        guard let server = try SelfSignedServer.start(commonName: "nas.example.test") else { return }
        defer { server.stop() }

        let store = ServerTrustStore(defaults: UserDefaults(suiteName: "handshake-\(UUID().uuidString)")!)
        let session = URLSession(
            configuration: .ephemeral,
            delegate: ServerTrustDelegate(store: store),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        await #expect(throws: (any Error).self) { try await session.data(from: server.url) }
        let refused = try #require(store.refused(for: "127.0.0.1"))
        #expect(refused.certifiedName == nil)
    }
}

private struct SelfSignedServer {
    let url: URL
    private let process: Process
    private let directory: URL

    static func start(commonName: String = "127.0.0.1") throws -> SelfSignedServer? {
        let tools = ["/usr/bin/openssl", "/usr/bin/python3"]
        guard tools.allSatisfy({ FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-tls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let pem = directory.appendingPathComponent("server.pem")
        let openssl = Process()
        openssl.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        openssl.arguments = [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", pem.path, "-out", pem.path,
            "-days", "1", "-subj", "/CN=\(commonName)",
            "-addext", commonName == "127.0.0.1"
                ? "subjectAltName=IP:127.0.0.1"
                : "subjectAltName=DNS:\(commonName)"
        ]
        openssl.standardOutput = FileHandle.nullDevice
        openssl.standardError = FileHandle.nullDevice
        try openssl.run()
        openssl.waitUntilExit()
        guard openssl.terminationStatus == 0 else { return nil }

        let script = """
        import http.server, ssl, sys
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain('\(pem.path)')
        server = http.server.HTTPServer(('127.0.0.1', 0), http.server.SimpleHTTPRequestHandler)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        print(server.server_address[1], flush=True)
        server.serve_forever()
        """
        let python = Process()
        python.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        python.arguments = ["-c", script]
        python.currentDirectoryURL = directory
        let output = Pipe()
        python.standardOutput = output
        python.standardError = FileHandle.nullDevice
        try python.run()

        // The server prints the port it landed on once it is listening.
        guard let line = output.fileHandleForReading.availableData
            .split(separator: UInt8(ascii: "\n")).first,
            let port = Int(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespaces)),
            let url = URL(string: "https://127.0.0.1:\(port)/")
        else {
            python.terminate()
            return nil
        }
        return SelfSignedServer(url: url, process: python, directory: directory)
    }

    func stop() {
        process.terminate()
        try? FileManager.default.removeItem(at: directory)
    }
}