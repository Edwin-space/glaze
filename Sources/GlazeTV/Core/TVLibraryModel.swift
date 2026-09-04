import Foundation
import GlazeCore
import Observation

/// One library, whichever kind of server it came from.
///
/// The screens used to read straight off the DLNA browser, so everything the WebDAV
/// path knows — posters, plots, which episodes belong to which show — could not reach
/// them. Both sources now land in the same `MediaLibrary`, and the shelves only ever
/// see that. A DLNA share gets no artwork because none exists to get; it still gets its
/// episodes gathered into shows.
@Observable
@MainActor
final class TVLibraryModel {
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

    /// How to actually play each item. Kept beside the library rather than inside it
    /// because a playback URL carries credentials and the library is passed to views.
    private var resources: [String: NetworkMediaResource] = [:]
    private var loadTask: Task<Void, Never>?

    func resource(for item: MediaLibraryItem) -> NetworkMediaResource? {
        resources[item.id]
    }

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    // MARK: - DLNA

    /// DLNA cannot answer what sits beside a film, so there are no posters, no plots
    /// and no subtitles here — only names, which the index can still make sense of.
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
            let loader = WebDAVLibraryLoader()
            do {
                let library = try await loader.load(
                    root: connection.rootURL,
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

    /// VLC is handed the credentials inside the URL, which is the only form it takes.
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
        default: L10n.string("webdav.error.network")
        }
    }
}
