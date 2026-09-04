import Foundation
import Observation

/// Browsing a NAS over WebDAV.
///
/// Shaped like `NetworkMediaBrowserModel` on purpose — the same screens drive both, and
/// the difference between them is what the viewer gets, not how they move around.
@MainActor
@Observable
public final class WebDAVBrowserModel {
    public struct Level: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let url: URL
        public let entries: [WebDAVEntry]
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready
    }

    public private(set) var levels: [Level] = []
    public private(set) var phase: Phase = .idle
    public private(set) var errorMessage: String?

    public var connection: WebDAVConnection?

    private let client: WebDAVClient
    private let credentials: WebDAVCredentialStore
    private let cacheLifetime: TimeInterval
    private var cache: [String: CachedFolder] = [:]
    private var activeRequestID: UUID?

    private struct CachedFolder {
        let entries: [WebDAVEntry]
        let loadedAt: Date
    }

    public init(
        client: WebDAVClient = WebDAVClient(),
        credentials: WebDAVCredentialStore = WebDAVCredentialStore(),
        cacheLifetime: TimeInterval = 60
    ) {
        self.client = client
        self.credentials = credentials
        self.cacheLifetime = cacheLifetime
    }

    public var currentEntries: [WebDAVEntry] {
        levels.last?.entries ?? []
    }

    public var folders: [WebDAVEntry] {
        currentEntries.filter(\.isDirectory)
    }

    public var videos: [WebDAVEntry] {
        currentEntries.filter(\.isVideo)
    }

    public var title: String {
        levels.last?.title ?? connection?.name ?? ""
    }

    public var canNavigateBack: Bool {
        levels.count > 1
    }

    public func open(_ connection: WebDAVConnection) async {
        await open(connection, at: connection.rootURL, title: connection.name)
    }

    /// Opens a saved subfolder directly without changing the connection's root.
    public func open(_ connection: WebDAVConnection, at url: URL, title: String) async {
        self.connection = connection
        levels = []
        await load(url, title: title)
    }

    public func open(_ entry: WebDAVEntry) async {
        guard entry.isDirectory else { return }
        await load(entry.url, title: entry.name)
    }

    public func navigateBack() {
        guard canNavigateBack else { return }
        activeRequestID = nil
        levels.removeLast()
        errorMessage = nil
        phase = .ready
    }

    /// Returns to an ancestor selected from the path bar or column browser.
    public func navigate(to levelID: String) {
        guard let index = levels.firstIndex(where: { $0.id == levelID }) else { return }
        activeRequestID = nil
        levels = Array(levels.prefix(through: index))
        errorMessage = nil
        phase = .ready
    }

    /// Reloads only the visible folder. Cached ancestors remain available for
    /// instant back navigation.
    public func reloadCurrent() async {
        guard let level = levels.last else { return }
        cache.removeValue(forKey: Self.cacheKey(for: level.url))
        levels.removeLast()
        await load(level.url, title: level.title)
    }

    /// Everything in the current folder that belongs to this film.
    public func companions(for video: WebDAVEntry) -> WebDAVCompanions {
        WebDAVCompanionFinder.find(for: video, among: currentEntries)
    }

    /// Reads a small companion file — a subtitle, an `.nfo`, a poster.
    public func data(for entry: WebDAVEntry) async -> Data? {
        guard let connection else { return nil }
        return try? await client.fetch(entry.url, credentials: credentialPair(for: connection))
    }

    private func load(_ url: URL, title: String) async {
        guard let connection else { return }

        let key = Self.cacheKey(for: url)
        if let cached = cache[key], Date().timeIntervalSince(cached.loadedAt) < cacheLifetime {
            levels.append(Level(id: key, title: title, url: url, entries: cached.entries))
            errorMessage = nil
            phase = .ready
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        phase = .loading
        errorMessage = nil

        do {
            let entries = try await client.list(url, credentials: credentialPair(for: connection))
            guard activeRequestID == requestID else { return }
            cache[key] = CachedFolder(entries: entries, loadedAt: Date())
            levels.append(Level(id: key, title: title, url: url, entries: entries))
            phase = .ready
        } catch {
            guard activeRequestID == requestID else { return }
            errorMessage = Self.message(for: error)
            phase = .ready
        }
    }

    private func credentialPair(for connection: WebDAVConnection) -> (String, String)? {
        guard !connection.username.isEmpty,
              let password = credentials.password(for: connection) else { return nil }
        return (connection.username, password)
    }

    private static func message(for error: Error) -> String {
        guard let webdav = error as? WebDAVError else {
            return L10n.string("webdav.error.network")
        }

        return switch webdav {
        case .unauthorized: L10n.string("webdav.error.unauthorized")
        case .notFound: L10n.string("webdav.error.not_found")
        case .notWebDAV: L10n.string("webdav.error.not_webdav")
        case .certificateMismatch: L10n.string("webdav.error.certificate")
        case .network: L10n.string("webdav.error.network")
        }
    }

    private static func cacheKey(for url: URL) -> String {
        var components = URLComponents(url: url.standardized, resolvingAgainstBaseURL: false)
        let normalizedScheme = components?.scheme?.lowercased()
        let normalizedHost = components?.host?.lowercased()
        components?.scheme = normalizedScheme
        components?.host = normalizedHost
        var path = components?.percentEncodedPath ?? url.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        components?.percentEncodedPath = path
        return components?.string ?? url.standardized.absoluteString
    }
}
