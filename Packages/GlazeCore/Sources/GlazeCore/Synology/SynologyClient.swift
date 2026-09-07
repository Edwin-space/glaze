import Foundation

/// A Synology NAS reached the way DS File reaches it.
///
/// WebDAV has to be switched on in DSM before Glaze can see anything, and most
/// people never have. DSM's own web API is always there, so signing in with the
/// account already used for the NAS is enough — shared folders and all.
public struct SynologySession: Equatable, Sendable {
    public let baseURL: URL
    public let sid: String

    public init(baseURL: URL, sid: String) {
        self.baseURL = baseURL
        self.sid = sid
    }
}

/// One entry in a shared folder.
public struct SynologyEntry: Equatable, Sendable, Identifiable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let byteCount: Int64?
    public let modifiedAt: Date?

    public var id: String { path }

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        byteCount: Int64? = nil,
        modifiedAt: Date? = nil
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }

    /// Synology's own bookkeeping folders, and what a Mac leaves behind.
    public var isHidden: Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix(".")
            || lowered.hasPrefix("._")
            || Self.skippedNames.contains(lowered)
    }

    public var isVideo: Bool {
        !isDirectory && !isHidden && MediaFileTypes.isVideo(URL(fileURLWithPath: name))
    }

    static let skippedNames: Set<String> = [
        "@eadir", "#recycle", "@recycle", "#snapshot", "surveillance", "thumbs.db", "desktop.ini"
    ]
}

public enum SynologyError: Error, Equatable, Sendable {
    case badCredentials
    /// The account has two-factor sign-in switched on; DSM wants the six digits.
    case needsOneTimeCode
    case oneTimeCodeRejected
    case accountDisabled
    /// Whatever answered is not a DSM box.
    case notSynology
    /// iOS refuses plain HTTP to an address outside the local network.
    case insecureConnectionBlocked
    case api(code: Int)
    case transport(String)
}

public struct SynologyClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Signing in

    /// - Parameter oneTimeCode: the six digits from the authenticator, when DSM has
    ///   asked for them. `needsOneTimeCode` is thrown the first time so the caller
    ///   can ask.
    public func logIn(
        to baseURL: URL,
        account: String,
        password: String,
        oneTimeCode: String? = nil
    ) async throws -> SynologySession {
        var fields = [
            "api": "SYNO.API.Auth",
            "version": "6",
            "method": "login",
            "account": account,
            "passwd": password,
            "session": "FileStation",
            "format": "sid",
        ]
        if let oneTimeCode, !oneTimeCode.isEmpty {
            fields["otp_code"] = oneTimeCode
        }

        // Sent as a form body rather than a query string: DSM accepts either, and a
        // password in a URL ends up in proxy logs and crash reports.
        let payload = try await post(endpoint("auth.cgi", on: baseURL), fields: fields)
        guard let sid = (payload["sid"] as? String) else { throw SynologyError.notSynology }
        return SynologySession(baseURL: baseURL, sid: sid)
    }

    public func logOut(_ session: SynologySession) async {
        _ = try? await get(
            endpoint("auth.cgi", on: session.baseURL),
            query: [
                "api": "SYNO.API.Auth", "version": "6", "method": "logout",
                "session": "FileStation", "_sid": session.sid,
            ]
        )
    }

    // MARK: - Browsing

    /// The shared folders the account can see — `video`, `photo`, whatever they made.
    public func shares(_ session: SynologySession) async throws -> [SynologyEntry] {
        let payload = try await get(
            endpoint("entry.cgi", on: session.baseURL),
            query: [
                "api": "SYNO.FileStation.List", "version": "2", "method": "list_share",
                "additional": "[\"time\"]", "_sid": session.sid,
            ]
        )
        return (payload["shares"] as? [[String: Any]] ?? []).compactMap(Self.entry(from:))
    }

    public func list(_ path: String, session: SynologySession) async throws -> [SynologyEntry] {
        let payload = try await get(
            endpoint("entry.cgi", on: session.baseURL),
            query: [
                "api": "SYNO.FileStation.List", "version": "2", "method": "list",
                "folder_path": path, "additional": "[\"size\",\"time\"]", "_sid": session.sid,
            ]
        )
        return (payload["files"] as? [[String: Any]] ?? []).compactMap(Self.entry(from:))
    }

    /// The address to hand the player, or to read a subtitle from.
    ///
    /// `mode=open` makes DSM stream rather than offer a download, which is what lets
    /// VLC seek in the file instead of waiting for all of it.
    public func mediaURL(for path: String, session: SynologySession) -> URL {
        var components = URLComponents(
            url: endpoint("entry.cgi", on: session.baseURL),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Download"),
            URLQueryItem(name: "version", value: "2"),
            URLQueryItem(name: "method", value: "download"),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "mode", value: "open"),
            URLQueryItem(name: "_sid", value: session.sid),
        ]
        return components.url!
    }

    public func fetch(
        _ path: String,
        session: SynologySession,
        maximumBytes: Int = 4 * 1_024 * 1_024
    ) async throws -> Data {
        let (data, response) = try await load(URLRequest(url: mediaURL(for: path, session: session)))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SynologyError.api(code: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data.count > maximumBytes ? data.prefix(maximumBytes) : data
    }

    // MARK: - Talking to DSM

    private func endpoint(_ name: String, on baseURL: URL) -> URL {
        baseURL.appendingPathComponent("webapi").appendingPathComponent(name)
    }

    private func get(_ url: URL, query: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await send(URLRequest(url: components.url!))
    }

    private func post(_ url: URL, fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await load(request)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SynologyError.notSynology
        }
        if root["success"] as? Bool == true {
            return root["data"] as? [String: Any] ?? [:]
        }
        let code = (root["error"] as? [String: Any])?["code"] as? Int ?? -1
        throw Self.error(forCode: code)
    }

    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            // Anything outside the local network has to be reached over HTTPS; iOS
            // refuses the plain-HTTP address DSM offers by default, and the error it
            // gives says nothing a person could act on.
            if error.code == .appTransportSecurityRequiresSecureConnection {
                throw SynologyError.insecureConnectionBlocked
            }
            throw SynologyError.transport(error.localizedDescription)
        } catch {
            throw SynologyError.transport(error.localizedDescription)
        }
    }

    private static func error(forCode code: Int) -> SynologyError {
        switch code {
        case 400, 401: .badCredentials
        case 402: .accountDisabled
        case 403: .needsOneTimeCode
        case 404: .oneTimeCodeRejected
        default: .api(code: code)
        }
    }

    private static func entry(from raw: [String: Any]) -> SynologyEntry? {
        guard let path = raw["path"] as? String, let name = raw["name"] as? String else { return nil }
        let additional = raw["additional"] as? [String: Any]
        let time = additional?["time"] as? [String: Any]
        let modified = (time?["mtime"] as? Double).map(Date.init(timeIntervalSince1970:))

        return SynologyEntry(
            path: path,
            name: name,
            isDirectory: raw["isdir"] as? Bool ?? false,
            byteCount: (additional?["size"] as? NSNumber)?.int64Value,
            modifiedAt: modified
        )
    }
}
