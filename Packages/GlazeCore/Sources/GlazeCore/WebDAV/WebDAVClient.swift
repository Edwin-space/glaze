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

    public init(id: String = UUID().uuidString, name: String, rootURL: URL, username: String) {
        self.id = id
        self.name = name
        // WebDAV collection URLs must end in a slash; a server given one without it
        // either redirects or answers about the parent.
        self.rootURL = rootURL.hasDirectoryPath ? rootURL : URL(string: rootURL.absoluteString + "/") ?? rootURL
        self.username = username
    }
}

public enum WebDAVError: Error, Sendable, Equatable {
    case unauthorized
    case notFound
    case notWebDAV
    case network(String)
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
            throw WebDAVError.network(error.localizedDescription)
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
            throw WebDAVError.network(error.localizedDescription)
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
