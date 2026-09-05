import Foundation

/// A NAS folder reachable over WebDAV.
///
/// The password is deliberately not part of this. It belongs in the keychain, and a
/// model that carries it ends up written into preferences by accident.
public struct WebDAVConnection: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    /// What the viewer calls it.
    public var name: String
    /// The folder to start browsing from.
    public var rootURL: URL
    public var username: String
    /// Which folder under the root holds the films, when the viewer has said.
    ///
    /// A WebDAV root is every share on the NAS — photos, home directories, a music
    /// library, a wastebasket. Reading a library from there means reading the whole
    /// disk, which is slow enough to look broken and heavy enough to be killed for it.
    /// Optional so connections saved before this existed still decode.
    public var libraryPath: String?

    /// Where a library scan should start.
    public var libraryURL: URL {
        guard let libraryPath, !libraryPath.isEmpty else { return rootURL }
        let url = rootURL.appendingPathComponent(libraryPath, isDirectory: true)
        return url.hasDirectoryPath ? url : URL(string: url.absoluteString + "/") ?? url
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        rootURL: URL,
        username: String,
        libraryPath: String? = nil
    ) {
        self.id = id
        self.name = name
        // WebDAV collection URLs must end in a slash; a server given one without it
        // either redirects or answers about the parent.
        self.rootURL = rootURL.hasDirectoryPath ? rootURL : URL(string: rootURL.absoluteString + "/") ?? rootURL
        self.username = username
        self.libraryPath = libraryPath
    }
}

public enum WebDAVError: Error, Sendable, Equatable {
    case unauthorized
    case notFound
    case notWebDAV
    /// The server's certificate does not cover the address it was reached at.
    ///
    /// The usual cause is typing a NAS's IP when its certificate names a domain:
    /// a Synology with a real certificate for `home.example.com` fails on
    /// `https://192.168.0.100:5006/` and nothing about "could not connect" says why.
    case certificateMismatch
    case network(String)
}

extension WebDAVError {
    /// Reads a URLSession failure closely enough to say something useful about it.
    static func transport(_ error: Error) -> WebDAVError {
        guard let urlError = error as? URLError else { return .network(error.localizedDescription) }
        switch urlError.code {
        case .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .serverCertificateUntrusted,
             .secureConnectionFailed:
            return .certificateMismatch
        default:
            return .network(urlError.localizedDescription)
        }
    }
}

/// Lists folders on a WebDAV server.
///
/// Only listing and fetching. Writing is what the Mac does through the filesystem when
/// the share is mounted; the Apple TV has no business changing anything on the NAS.
public struct WebDAVClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// - Parameter credentials: sent as HTTP Basic. Many NAS boxes offer no other
    ///   scheme, which is also why the connection should be HTTPS.
    public func list(
        _ url: URL,
        credentials: (username: String, password: String)?
    ) async throws -> [WebDAVEntry] {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        // Depth 1 is this folder's children. Depth infinity would walk an entire NAS
        // and most servers refuse it outright.
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")

        // Asking for named properties rather than allprop: some servers answer allprop
        // with a great deal we do not use, and a few are slow about it.
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:"><D:prop>
        <D:displayname/><D:resourcetype/><D:getcontentlength/>
        <D:getcontenttype/><D:getlastmodified/>
        </D:prop></D:propfind>
        """.utf8)

        if let credentials {
            let pair = "\(credentials.username):\(credentials.password)"
            let encoded = Data(pair.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WebDAVError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.network("no response")
        }

        switch http.statusCode {
        case 207:
            break
        case 401, 403:
            throw WebDAVError.unauthorized
        case 404:
            throw WebDAVError.notFound
        case 405, 501:
            // The server answered, but does not speak WebDAV at this address — the
            // usual cause is a plain web server or the wrong path.
            throw WebDAVError.notWebDAV
        default:
            throw WebDAVError.network("HTTP \(http.statusCode)")
        }

        return WebDAVPropfindParser.parse(data, baseURL: url)
    }

    /// Writes a small file to the share.
    ///
    /// This is how a poster and an `.nfo` reach a NAS. Before it, metadata could only
    /// be written beside a film on a local disk, so the films that most needed it —
    /// the ones on the NAS — were the ones that could not have it.
    public func upload(
        _ data: Data,
        to url: URL,
        credentials: (username: String, password: String)?
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        if let credentials {
            let encoded = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw WebDAVError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.network("no response")
        }
        switch http.statusCode {
        // 200 replaced, 201 created, 204 replaced with no body — all success.
        case 200, 201, 204: return
        case 401, 403: throw WebDAVError.unauthorized
        case 404, 409: throw WebDAVError.notFound
        case 405, 501: throw WebDAVError.notWebDAV
        default: throw WebDAVError.network("HTTP \(http.statusCode)")
        }
    }

    /// Fetches a small file — a subtitle, an `.nfo`, a poster.
    ///
    /// - Parameter maximumBytes: a guard against a mistaken path pointing at a film.
    public func fetch(
        _ url: URL,
        credentials: (username: String, password: String)?,
        maximumBytes: Int = 8 * 1024 * 1024
    ) async throws -> Data {
        var request = URLRequest(url: url)
        if let credentials {
            let encoded = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WebDAVError.transport(error)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 401, 403: throw WebDAVError.unauthorized
            case 404: throw WebDAVError.notFound
            default: throw WebDAVError.network("HTTP \(http.statusCode)")
            }
        }

        guard data.count <= maximumBytes else {
            throw WebDAVError.network("response too large")
        }

        return data
    }
}
