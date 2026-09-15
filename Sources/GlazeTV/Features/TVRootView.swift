import GlazeCore
import SwiftUI

struct TVRootView: View {
    @State private var preferences = TVUserPreferences()
    @State private var media = NetworkMediaBrowserModel()
    @State private var library = TVLibraryModel()
    @State private var artwork = TVArtworkLoader()
    @State private var connections = TVWebDAVConnections()
    @State private var synologyConnections = SynologyConnectionStore()
    @State private var browser = TVNetworkBrowser()

    var body: some View {
        Group {
            if preferences.onboardingCompleted {
                TVAppShell(
                    media: media,
                    library: library,
                    connections: connections,
                    synologyConnections: synologyConnections,
                    browser: browser,
                    preferences: preferences
                )
            } else {
                TVOnboardingView(
                    model: media,
                    preferences: preferences,
                    onPaired: { payload in
                        TVPairingAdoption.adopt(
                            payload,
                            connections: connections,
                            synologyConnections: synologyConnections,
                            library: library,
                            artwork: artwork,
                            browser: browser
                        )
                        preferences.finishOnboarding(serverID: nil)
                    }
                )
            }
        }
        .environment(artwork)
        .animation(.easeInOut(duration: 0.3), value: preferences.onboardingCompleted)
    }
}

/// The Apple TV app's shape: a tab bar across the top that the focus engine reaches by
/// moving up, and nothing overlaying the content while you browse.
///
/// This replaced a slide-over sidebar. The sidebar covered a fifth of the screen
/// whenever it was open, and its search field swallowed the arrow keys — focus went in
/// and did not come out. A tab bar is also simply what a viewer expects here.
private struct TVAppShell: View {
    let media: NetworkMediaBrowserModel
    let library: TVLibraryModel
    let connections: TVWebDAVConnections
    let synologyConnections: SynologyConnectionStore
    let browser: TVNetworkBrowser
    @Bindable var preferences: TVUserPreferences

    @Environment(TVArtworkLoader.self) private var artwork
    @State private var selection: TVTab = .home
    @State private var route: TVLibrarySelection?
    /// A NAS whose library folder has not been chosen yet.
    @State private var folderChoice: WebDAVConnection?
    @State private var isPairing = false
    @State private var folderPath = NavigationPath()
    /// A film chosen in the folder browser, on its way to the player.
    @State private var browsing: TVBrowsedFilm?
    /// Bumped when that player closes so the folder list redraws its watched marks.
    @State private var watchRevision = 0

    var body: some View {
        TabView(selection: $selection) {
            Tab(L10n.string("tv.navigation.home"), systemImage: "house.fill", value: TVTab.home) {
                TVHomeView(
                    library: library,
                    preferences: preferences,
                    onOpenSources: { selection = .sources },
                    onRetry: { Task { await loadPreferredSource() } },
                    isBrowsable: browser.isConnected,
                    onOpenFolders: { selection = .folders },
                    onSelect: { route = $0 }
                )
            }

            Tab(L10n.string("tv.navigation.movies"), systemImage: "film.fill", value: TVTab.movies) {
                TVCollectionView(
                    title: L10n.string("tv.navigation.movies"),
                    movies: library.library.movies,
                    series: [],
                    onSelect: { route = $0 }
                )
            }

            Tab(L10n.string("tv.navigation.series"), systemImage: "tv.fill", value: TVTab.series) {
                TVCollectionView(
                    title: L10n.string("tv.navigation.series"),
                    movies: [],
                    series: library.library.series,
                    onSelect: { route = $0 }
                )
            }

            Tab(L10n.string("tv.navigation.sources"), systemImage: "externaldrive.fill", value: TVTab.sources) {
                TVMediaSourcesView(
                    model: media,
                    library: library,
                    preferences: preferences,
                    onOpenPairing: { isPairing = true },
                    onUseWebDAV: { connection in
                        connections.reload()
                        let saved = connections.connections.first { $0.id == connection.id } ?? connection
                        if saved.libraryPath == nil {
                            folderChoice = saved
                        } else {
                            useWebDAV(saved)
                            selection = .home
                        }
                    },
                    onUseDLNA: { server in
                        browser.use(dlna: server)
                        selection = .folders
                    }
                )
            }

            // Folder browsing: one request for the folder in front of you, however
            // many thousands of films sit below it. The shelves are built by reading
            // the whole tree, which is right for a library someone arranged and wrong
            // for finding one file on a NAS.
            Tab(L10n.string("ios.local.folder"), systemImage: "folder.fill", value: TVTab.folders) {
                NavigationStack(path: $folderPath) {
                    Group {
                        if browser.isConnected {
                            TVNetworkBrowserView(
                                browser: browser,
                                folder: TVNetworkFolder(path: browser.rootPath, name: ""),
                                onPlay: { browsing = TVBrowsedFilm(queue: $0) },
                                watchRevision: watchRevision
                            )
                        } else {
                            TVFolderBrowsingUnavailable(onOpenSources: { selection = .sources })
                        }
                    }
                    .navigationDestination(for: TVNetworkFolder.self) { folder in
                        TVNetworkBrowserView(
                            browser: browser,
                            folder: folder,
                            onPlay: { browsing = TVBrowsedFilm(queue: $0) },
                            watchRevision: watchRevision
                        )
                    }
                }
            }

            Tab(L10n.string("settings.title"), systemImage: "gearshape.fill", value: TVTab.settings) {
                TVSettingsView(preferences: preferences, onOpenPairing: { isPairing = true })
            }

            Tab(value: TVTab.search, role: .search) {
                TVSearchView(library: library, onSelect: { route = $0 })
            }
        }
        .background(TVTheme.ground.ignoresSafeArea())
        .task(id: preferences.preferredServerID) {
            await loadPreferredSource()
        }
        // As soon as a server is chosen or restored, not when its catalogue is done.
        .onChange(of: media.selectedServer?.id) { _, _ in
            adoptDLNAIfNeeded()
        }
        .onChange(of: media.homeNodes.count) { _, _ in
            adoptDLNAIfNeeded()
        }
        .fullScreenCover(isPresented: $isPairing) {
            TVPairingView { payload in
                TVPairingAdoption.adopt(
                    payload,
                    connections: connections,
                    synologyConnections: synologyConnections,
                    library: library,
                    artwork: artwork,
                    browser: browser
                )
                selection = .home
            }
        }
        .fullScreenCover(item: $folderChoice) { connection in
            TVLibraryFolderPicker(
                connection: connection,
                password: connections.password(for: connection)
            ) { path in
                var updated = connection
                updated.libraryPath = path
                connections.save(updated, password: nil)
                useWebDAV(updated)
                selection = .home
            }
        }
        .fullScreenCover(item: $browsing, onDismiss: { watchRevision += 1 }) { film in
            if let current = film.queue.current {
                TVPlayerView(
                    resource: current.resource,
                    title: current.title,
                    startAt: PlaybackPositionStore().position(for: .network(current.resource)) ?? 0,
                    externalSubtitleURL: preferences.automaticallySelectSubtitles
                        ? SubtitleChoice.preferred(
                            among: current.resource.subtitleResources,
                            language: preferences.defaultSubtitleLanguageCode
                        )
                        : nil,
                    preferredSubtitleLanguageCode: preferences.defaultSubtitleLanguageCode,
                    automaticallySelectSubtitles: preferences.automaticallySelectSubtitles,
                    preferredSubtitleScale: preferences.subtitleScale,
                    queue: film.queue
                )
            }
        }
        .fullScreenCover(item: $route) { selection in
            switch selection {
            case .movie(let item):
                TVDetailView(
                    item: item,
                    resource: library.resource(for: item),
                    preferences: preferences
                )
            case .series(let show):
                TVSeriesView(
                    series: show,
                    library: library,
                    preferences: preferences
                )
            }
        }
    }

    /// A NAS the viewer typed in wins over a DLNA server that merely answered a
    /// broadcast: it is the one that can carry posters and subtitles.
    private func loadPreferredSource() async {
        // A NAS added on the previous screen was saved through that screen's own copy
        // of the store; this one has to look again before deciding there is none.
        connections.reload()

        if let connection = connections.connections.first {
            // Asked once, on the first run with this NAS. Scanning a whole share is
            // what made the television give up partway through.
            if connection.libraryPath == nil {
                folderChoice = connection
            } else {
                useWebDAV(connection)
            }
            return
        }

        if let preferredID = preferences.preferredServerID {
            _ = await media.restorePreferredServer(id: preferredID)
        } else {
            await media.discoverIfNeeded()
        }
        adoptDLNAIfNeeded()
    }

    /// Artwork travels behind the same login as the films, so the loader is told about
    /// the connection at the moment the library adopts it — not once at launch, when
    /// there may not be one yet.
    private func useWebDAV(_ connection: WebDAVConnection) {
        let password = connections.password(for: connection)
        artwork.use(username: connection.username, password: password)
        library.load(connection, password: password)
        browser.use(webDAV: connection, password: password)
    }

    private func adoptDLNAIfNeeded() {
        guard connections.connections.isEmpty, let server = media.selectedServer else { return }
        // Before anything else, and without waiting for the shelves. This used to sit
        // behind the guard on `homeNodes` below, so a server whose films were deeper
        // than the catalogue reaches — every Synology browsed by folder — left the
        // folder tab empty as well as the shelves.
        browser.use(dlna: server)

        guard !media.homeNodes.isEmpty else { return }
        library.adopt(dlnaNodes: media.homeNodes, serverName: server.friendlyName)
    }
}

/// A film picked out of the folder browser, wrapped so it can drive a cover.
private struct TVBrowsedFilm: Identifiable {
    let queue: PlaybackQueue
    var id: String { queue.current?.id ?? "" }
}

/// Said plainly rather than showing an empty list: there is no server yet.
private struct TVFolderBrowsingUnavailable: View {
    let onOpenSources: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L10n.string("tv.folders.no_server"))
                .font(.system(size: 44, weight: .bold))
            Button(L10n.string("tv.navigation.sources"), action: onOpenSources)
                .buttonStyle(.card)
        }
        .padding(84)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TVTheme.ground.ignoresSafeArea())
    }
}

private enum TVTab: Hashable {
    case home
    case movies
    case series
    case sources
    case folders
    case settings
    case search
}

extension TVLibrarySelection: Identifiable {
    var id: String {
        switch self {
        case .movie(let item): "movie:\(item.id)"
        case .series(let show): "series:\(show.id)"
        }
    }
}


/// What the television does with a server the phone handed it.
///
/// Saved first, so it survives the next launch, and then opened — the point of
/// pairing is that the viewer is already sitting there wanting to watch something.
@MainActor
enum TVPairingAdoption {
    static func adopt(
        _ payload: PairingPayload,
        connections: TVWebDAVConnections,
        synologyConnections: SynologyConnectionStore,
        library: TVLibraryModel,
        artwork: TVArtworkLoader,
        browser: TVNetworkBrowser
    ) {
        switch payload.server {
        case .webDAV(let rootURL, let username, let password, let libraryPath):
            var connection = WebDAVConnection(name: payload.name, rootURL: rootURL, username: username)
            connection.libraryPath = libraryPath
            connections.save(connection, password: password)
            artwork.use(username: username, password: password)
            library.load(connection, password: password)
            browser.use(webDAV: connection, password: password)

        case .synology(let baseURL, let account, let password, let libraryPath):
            let connection = SynologyConnection(
                name: payload.name,
                baseURL: baseURL,
                account: account,
                libraryPath: libraryPath
            )
            synologyConnections.save(connection, password: password)
            // DSM's addresses carry their own session token, so the artwork loader
            // needs no separate login.
            artwork.use(username: "", password: nil)
            Task {
                do {
                    let session = try await SynologyClient().logIn(
                        to: baseURL, account: account, password: password
                    )
                    library.loadSynology(
                        name: payload.name,
                        session: session,
                        path: libraryPath ?? "/"
                    )
                    browser.use(
                        synology: payload.name,
                        session: session,
                        rootPath: libraryPath ?? ""
                    )
                } catch {
                    library.reportFailure(error)
                }
            }
        }
    }
}
