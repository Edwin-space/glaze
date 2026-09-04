import Foundation

/// Downloads WebDAV sidecar subtitles into a disposable local cache.
///
/// Playback starts before this actor is called. Keeping the network read here means a
/// slow subtitle file cannot delay VLC, while the local result can still use the same
/// parser and translation pipeline as a subtitle selected from disk.
///
/// Conversion is injected because it is the one part that is not portable: the Mac
/// hands in ffmpeg, which Apple TV has no process to run.
public actor NetworkSubtitleLoader {
    public typealias SubtitleConverter = @Sendable (_ source: URL, _ destination: URL) async throws -> Void

    public enum LoaderError: Error, Equatable {
        case invalidResponse
        case httpStatus(Int)
        case responseTooLarge
        case conversionUnavailable
    }

    private let session: URLSession
    private let convertToSRT: SubtitleConverter?
    private let cacheDirectory: URL
    private let maximumBytes: Int

    /// A subtitle answered slowly is worth abandoning; the film is already playing.
    /// URLSession's own default would hold the panel for a minute.
    public static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    public init(
        session: URLSession? = nil,
        convertToSRT: SubtitleConverter? = nil,
        cacheDirectory: URL? = nil,
        maximumBytes: Int = 16 * 1_024 * 1_024
    ) {
        self.session = session ?? Self.defaultSession()
        self.convertToSRT = convertToSRT
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory()
        self.maximumBytes = maximumBytes
    }

    public func load(_ resource: NetworkSubtitleResource) async throws -> URL {
        let destination = cacheURL(for: resource)
        let outputURL = convertedURLIfNeeded(for: destination)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }
        guard outputURL == destination || convertToSRT != nil else {
            throw LoaderError.conversionUnavailable
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try await download(from: resource.url)
        try data.write(to: destination, options: .atomic)

        guard outputURL != destination, let convertToSRT else { return destination }
        do {
            try await convertToSRT(destination, outputURL)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return outputURL
    }

    /// Credentials travel inside the URL because that is what the player hands VLC.
    /// They are moved into an Authorization header here so they never reach a log or
    /// a proxy's request line.
    private func download(from url: URL) async throws -> Data {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let username = components?.user
        let password = components?.password
        components?.user = nil
        components?.password = nil
        guard let requestURL = components?.url else { throw LoaderError.invalidResponse }

        var request = URLRequest(url: requestURL)
        if let username, let password {
            let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LoaderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LoaderError.httpStatus(http.statusCode)
        }
        // A server that declares its size lets the transfer be refused before it starts.
        if http.expectedContentLength > Int64(maximumBytes) {
            throw LoaderError.responseTooLarge
        }

        var data = Data()
        for try await byte in stream {
            data.append(byte)
            if data.count > maximumBytes { throw LoaderError.responseTooLarge }
        }
        return data
    }

    private func cacheURL(for resource: NetworkSubtitleResource) -> URL {
        let root = cacheDirectory
            .appendingPathComponent(Self.fnv1aHash(resource.url.absoluteString), isDirectory: true)
        let fallback = resource.url.lastPathComponent.isEmpty
            ? "subtitle.srt"
            : resource.url.lastPathComponent
        let filename = resource.displayName.isEmpty ? fallback : resource.displayName
        return root.appendingPathComponent(filename.replacingOccurrences(of: "/", with: "-"))
    }

    private func convertedURLIfNeeded(for sourceURL: URL) -> URL {
        switch sourceURL.pathExtension.lowercased() {
        case "ass", "ssa":
            sourceURL.deletingPathExtension().appendingPathExtension("srt")
        default:
            sourceURL
        }
    }

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Glaze", isDirectory: true)
            .appendingPathComponent("NetworkSubtitles", isDirectory: true)
    }

    private static func fnv1aHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
