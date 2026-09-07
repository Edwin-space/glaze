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
        case device
        case dlna(serverName: String)
        case webDAV(connectionName: String)
        case synology(connectionName: String)
    }

    /// Where films copied onto the phone live: the app's own Documents folder,
    /// which is what Finder shows over USB and what the Files app calls
    /// "On My iPhone → Glaze".
    static var deviceLibraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private(set) var library = MediaLibrary()
    private(set) var phase: Phase = .idle
    private(set) var source: Source = .none

    /// How to play each item. Kept apart from the library because a playback URL
    /// carries credentials and the library is handed to views.
    private var resources: [String: NetworkMediaResource] = [:]
    private var loadTask: Task<Void, Never>?
    /// Kept so a folder can be listed again later — the subtitle picker needs to see
    /// every subtitle beside a film, not only the ones whose name matched it.
    private var webDAV: (connection: WebDAVConnection, password: String?)?
    /// Kept for the same reason as the WebDAV one: the subtitle picker lists the
    /// film's folder again, and that needs the signed-in session.
    private var synology: (name: String, session: SynologySession)?

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
        webDAV = nil
        source = .dlna(serverName: serverName)
        phase = .ready
    }

    // MARK: - This device

    /// Reads the app's own folder. Films arrive there over USB or through the
    /// Files app, and once there they are read exactly as a NAS folder is —
    /// grouped into films and shows, with whatever subtitle sits beside them.
    func loadDevice() {
        loadTask?.cancel()
        phase = .loading(foldersRead: 0)
        source = .device
        webDAV = nil

        let root = Self.deviceLibraryURL
        loadTask = Task { [weak self] in
            let library = await LocalLibraryLoader().load(root: root) { [weak self] read in
                Task { @MainActor in self?.noteProgress(read) }
            }
            guard let self, !Task.isCancelled else { return }
            adoptDevice(library)
        }
    }

    private func adoptDevice(_ library: MediaLibrary) {
        var resources: [String: NetworkMediaResource] = [:]
        for item in library.movies + library.series.flatMap(\.allEpisodes) {
            resources[item.id] = NetworkMediaResource(
                serverID: "device",
                objectID: item.id,
                playbackURL: item.playbackURL,
                byteCount: item.byteCount,
                duration: item.duration,
                dateAdded: item.dateAdded,
                subtitleResources: item.subtitleURLs.map { url in
                    NetworkSubtitleResource(
                        url: url,
                        displayName: url.lastPathComponent,
                        languageCode: SubtitleFile.manual(url: url).languageCode
                    )
                }
            )
        }
        self.resources = resources
        self.library = library
        phase = .ready
    }

    // MARK: - Synology

    /// Reads a shared folder over DSM's own API, so nothing has to be switched on in
    /// the NAS first.
    func loadSynology(name: String, session: SynologySession, path: String) {
        loadTask?.cancel()
        phase = .loading(foldersRead: 0)
        source = .synology(connectionName: name)
        webDAV = nil
        synology = (name, session)

        loadTask = Task { [weak self] in
            do {
                let library = try await SynologyLibraryLoader().load(
                    root: path,
                    session: session
                ) { [weak self] read in
                    Task { @MainActor in self?.noteProgress(read) }
                }
                guard let self, !Task.isCancelled else { return }
                adoptSynology(library, session: session)
            } catch {
                guard let self, !Task.isCancelled else { return }
                phase = .failed(Self.message(forSynology: error))
            }
        }
    }

    private func adoptSynology(_ library: MediaLibrary, session: SynologySession) {
        var resources: [String: NetworkMediaResource] = [:]
        for item in library.movies + library.series.flatMap(\.allEpisodes) {
            // The addresses already carry the session token, so nothing else is needed
            // to hand them to the player.
            resources[item.id] = NetworkMediaResource(
                serverID: session.baseURL.absoluteString,
                objectID: item.id,
                playbackURL: item.playbackURL,
                byteCount: item.byteCount,
                duration: item.duration,
                dateAdded: item.dateAdded,
                subtitleResources: item.subtitleURLs.map { url in
                    NetworkSubtitleResource(
                        url: url,
                        displayName: url.lastPathComponent,
                        languageCode: SubtitleFile.manual(url: url).languageCode
                    )
                }
            )
        }
        self.resources = resources
        self.library = library
        phase = .ready
    }

    /// Lets a failed sign-in show up where every other library failure does.
    func reportSynologyFailure(_ error: Error) {
        phase = .failed(Self.message(forSynology: error))
    }

    static func message(forSynology error: Error) -> String {
        switch error {
        case SynologyError.badCredentials: L10n.string("synology.error.credentials")
        case SynologyError.needsOneTimeCode: L10n.string("synology.error.otp_required")
        case SynologyError.oneTimeCodeRejected: L10n.string("synology.error.otp_rejected")
        case SynologyError.accountDisabled: L10n.string("synology.error.disabled")
        case SynologyError.notSynology: L10n.string("synology.error.not_synology")
        case SynologyError.insecureConnectionBlocked: L10n.string("synology.error.needs_https")
        default: L10n.string("webdav.error.network")
        }
    }

    // MARK: - WebDAV

    func load(_ connection: WebDAVConnection, password: String?) {
        loadTask?.cancel()
        phase = .loading(foldersRead: 0)
        source = .webDAV(connectionName: connection.name)
        webDAV = (connection, password)

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

    // MARK: - Subtitles

    /// Every subtitle sitting in the same folder as the film, whatever it is called.
    ///
    /// The library only attaches a subtitle whose name follows the film's, which is the
    /// right rule for building a library and the wrong one when a viewer downloaded
    /// `기생충.srt` to sit beside `Parasite.2019.1080p.mkv`. This lists the folder
    /// again and offers the lot.
    func subtitleCandidates(for item: MediaLibraryItem) async -> [IOSSubtitleCandidate] {
        if let synology { return await synologyCandidates(for: item, session: synology.session) }
        guard let webDAV else { return [] }
        let folder = item.playbackURL.deletingLastPathComponent()
        let credentials = webDAV.password.map { (username: webDAV.connection.username, password: $0) }
        guard let entries = try? await WebDAVClient().list(folder, credentials: credentials) else { return [] }

        let matched = Set(item.subtitleURLs.map(\.absoluteString))
        return entries
            .filter { !$0.isDirectory && !$0.isHidden && Self.subtitleExtensions.contains($0.url.pathExtension.lowercased()) }
            .sorted { $0.name < $1.name }
            .map { entry in
                IOSSubtitleCandidate(
                    id: entry.url.absoluteString,
                    name: entry.name,
                    url: Self.authenticated(entry.url, connection: webDAV.connection, password: webDAV.password),
                    isBesideTheFilm: matched.contains(entry.url.absoluteString)
                )
            }
    }

    private func synologyCandidates(
        for item: MediaLibraryItem,
        session: SynologySession
    ) async -> [IOSSubtitleCandidate] {
        // The item's id is the file's path on the NAS, which is what DSM lists by.
        let folder = (item.id as NSString).deletingLastPathComponent
        let client = SynologyClient()
        guard let entries = try? await client.list(folder, session: session) else { return [] }

        let matched = Set(item.subtitleURLs.map(\.absoluteString))
        return entries
            .filter { !$0.isDirectory && !$0.isHidden && Self.subtitleExtensions.contains(($0.name as NSString).pathExtension.lowercased()) }
            .sorted { $0.name < $1.name }
            .map { entry in
                let url = client.mediaURL(for: entry.path, session: session)
                return IOSSubtitleCandidate(
                    id: entry.path,
                    name: entry.name,
                    url: url,
                    isBesideTheFilm: matched.contains(url.absoluteString)
                )
            }
    }

    private static let subtitleExtensions: Set<String> = ["srt", "vtt", "smi", "ass", "ssa", "sub"]
}

/// A subtitle file the viewer can attach by hand.
struct IOSSubtitleCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    /// True when the library already recognised this one as belonging to the film.
    let isBesideTheFilm: Bool
}
