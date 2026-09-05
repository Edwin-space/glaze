import Foundation
import GlazeCore
import Observation

/// One library, whichever kind of server it came from — the same arrangement the
/// Apple TV uses, because the work of turning a folder of files into films and shows
/// belongs to `GlazeCore` and not to any one screen.
@Observable
@MainActor
final class IOSLibraryModel {
    enum Phase: Equatable {
        case idle
        case loading(foldersRead: Int)
        case ready
        case failed(String)
    }

    enum Source: Equatable {
        case none
        case dlna(serverName: String)
        case webDAV(connectionName: String)
    }

    private(set) var library = MediaLibrary()
    private(set) var phase: Phase = .idle
    private(set) var source: Source = .none

    /// How to play each item. Kept apart from the library because a playback URL
    /// carries credentials and the library is handed to views.
    private var resources: [String: NetworkMediaResource] = [:]
    private var loadTask: Task<Void, Never>?

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    func resource(for item: MediaLibraryItem) -> NetworkMediaResource? {
        resources[item.id]
    }

    // MARK: - DLNA

    /// DLNA cannot say what sits beside a film, so there is no artwork and no plot
    /// here — only names, which the index can still make sense of.
    func adopt(dlnaNodes nodes: [NetworkMediaNode], serverName: String) {
        var items: [MediaLibraryItem] = []
        var resources: [String: NetworkMediaResource] = [:]

        for node in nodes {
            guard case .video(let resource) = node.kind else { continue }
            let id = "\(resource.serverID)#\(resource.objectID)"
            resources[id] = resource
            items.append(
                MediaLibraryItem(
                    id: id,
                    sourceName: node.title,
                    parsed: MediaTitleParser.parse(node.title),
                    playbackURL: resource.playbackURL,
                    dateAdded: resource.dateAdded,
                    byteCount: resource.byteCount,
                    duration: resource.duration
                )
            )
        }

        self.resources = resources
        library = MediaLibraryIndex.build(from: items)
        source = .dlna(serverName: serverName)
        phase = .ready
    }

    // MARK: - WebDAV

    func load(_ connection: WebDAVConnection, password: String?) {
        loadTask?.cancel()
        phase = .loading(foldersRead: 0)
        source = .webDAV(connectionName: connection.name)

        loadTask = Task { [weak self] in
            let credentials = password.map { (username: connection.username, password: $0) }
            do {
                let library = try await WebDAVLibraryLoader().load(
                    root: connection.libraryURL,
                    credentials: credentials
                ) { [weak self] read in
                    Task { @MainActor in self?.noteProgress(read) }
                }
                guard let self, !Task.isCancelled else { return }
                adopt(library, connection: connection, password: password)
            } catch {
                guard let self, !Task.isCancelled else { return }
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func noteProgress(_ foldersRead: Int) {
        guard case .loading = phase else { return }
        phase = .loading(foldersRead: foldersRead)
    }

    private func adopt(_ library: MediaLibrary, connection: WebDAVConnection, password: String?) {
        var resources: [String: NetworkMediaResource] = [:]
        for item in library.movies + library.series.flatMap(\.allEpisodes) {
            resources[item.id] = makeResource(for: item, connection: connection, password: password)
        }
        self.resources = resources
        self.library = library
        phase = .ready
    }

    /// VLC takes credentials inside the URL, which is the only form it accepts.
    private func makeResource(
        for item: MediaLibraryItem,
        connection: WebDAVConnection,
        password: String?
    ) -> NetworkMediaResource {
        NetworkMediaResource(
            serverID: connection.id,
            objectID: item.id,
            playbackURL: Self.authenticated(item.playbackURL, connection: connection, password: password),
            byteCount: item.byteCount,
            duration: item.duration,
            dateAdded: item.dateAdded,
            subtitleResources: item.subtitleURLs.map { url in
                NetworkSubtitleResource(
                    url: Self.authenticated(url, connection: connection, password: password),
                    displayName: url.lastPathComponent,
                    languageCode: SubtitleFile.manual(url: url).languageCode
                )
            }
        )
    }

    private static func authenticated(
        _ url: URL,
        connection: WebDAVConnection,
        password: String?
    ) -> URL {
        guard !connection.username.isEmpty, let password,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.user = connection.username
        components.password = password
        return components.url ?? url
    }

    private static func message(for error: Error) -> String {
        switch error {
        case WebDAVError.unauthorized: L10n.string("webdav.error.unauthorized")
        case WebDAVError.notFound: L10n.string("webdav.error.not_found")
        case WebDAVError.notWebDAV: L10n.string("webdav.error.not_webdav")
        case WebDAVError.certificateMismatch: L10n.string("webdav.error.certificate")
        default: L10n.string("webdav.error.network")
        }
    }
}
