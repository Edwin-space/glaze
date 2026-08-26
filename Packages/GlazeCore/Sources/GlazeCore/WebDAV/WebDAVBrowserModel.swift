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

    public init(
        client: WebDAVClient = WebDAVClient(),
        credentials: WebDAVCredentialStore = WebDAVCredentialStore()
    ) {
        self.client = client
        self.credentials = credentials
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
        self.connection = connection
        levels = []
        await load(connection.rootURL, title: connection.name)
    }

    public func open(_ entry: WebDAVEntry) async {
        guard entry.isDirectory else { return }
        await load(entry.url, title: entry.name)
    }

    public func navigateBack() {
        guard canNavigateBack else { return }
        levels.removeLast()
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

        phase = .loading
        errorMessage = nil

        do {
            let entries = try await client.list(url, credentials: credentialPair(for: connection))
            levels.append(Level(id: url.absoluteString, title: title, url: url, entries: entries))
            phase = .ready
        } catch {
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
        case .network: L10n.string("webdav.error.network")
        }
    }
}
