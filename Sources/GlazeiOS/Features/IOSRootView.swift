import GlazeBooks
import GlazeCore
import SwiftUI

/// A tab bar, because that is what a phone app is.
///
/// iPad gets the same thing: SwiftUI turns a `TabView` into a sidebar there when the
/// window is wide enough, which is the layout an iPad wants without a second code path.
struct IOSRootView: View {
    @State private var discovery = NetworkMediaBrowserModel()
    @State private var library = IOSLibraryModel()
    @State private var networkBrowser = IOSNetworkBrowser()
    @State private var artwork = IOSArtworkLoader()
    @State private var connections = WebDAVConnectionStore()
    @State private var synologyConnections = SynologyConnectionStore()
    @State private var preferences = IOSUserPreferences()
    @State private var books = IOSBookLibraryModel()
    @State private var covers = IOSBookCoverLoader()
    @State private var favorites = LibraryFavoriteStore()
    @State private var readingProgress = ReadingProgressStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: IOSTab = .local
    @State private var path = NavigationPath()
    @State private var bookPath = NavigationPath()

    /// Four places, each of which is one thing.
    ///
    /// There used to be a "library" whose contents depended on a source chosen in
    /// another tab — it showed the phone's files or a NAS depending on hidden state,
    /// and renamed itself to whichever it was. Nobody could tell what they were
    /// looking at. Local files and a server are used at different times, for different
    /// reasons; they are now different places.
    private enum IOSTab: Hashable {
        case local
        case network
        case books
        case settings
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(L10n.string("ios.local.title"), systemImage: "iphone", value: IOSTab.local) {
                NavigationStack {
                    IOSLocalBrowserView(folder: IOSLibraryModel.deviceLibraryURL, isRoot: true)
                }
            }

            // The one thing on this app that neither the Mac nor the television can
            // do: a phone and an iPad are what people actually read on.
            Tab(L10n.string("book.shelf.title"), systemImage: "books.vertical", value: IOSTab.books) {
                NavigationStack(path: $bookPath) {
                    IOSBookshelfView(
                        books: books,
                        onSelectCollection: { bookPath.append(IOSBookSelection.collection($0.id)) }
                    )
                    .navigationDestination(for: IOSBookSelection.self) { selection in
                        switch selection {
                        case .collection(let id):
                            if let collection = books.collection(withID: id) {
                                IOSBookCollectionView(collection: collection)
                            }
                        }
                    }
                }
            }

            Tab(L10n.string("ios.network.title"), systemImage: "externaldrive.connected.to.line.below", value: IOSTab.network) {
                NavigationStack(path: $path) {
                    IOSSourcesView(
                        discovery: discovery,
                        connections: connections,
                        synologyConnections: synologyConnections,
                        library: library,
                        // A UPnP server is browsed folder by folder like the other two.
                        // It used to be the odd one out — the same tab showed a poster
                        // grid or a folder list depending on which kind of server was
                        // picked, which is not a difference anyone asked for.
                        onUseDLNA: { server in
                            preferences.lastSource = "dlna"
                            networkBrowser.use(dlna: server)
                            openServerRoot()
                        },
                        onUseWebDAV: { connection in
                            connections.reload()
                            let saved = connections.connections.first { $0.id == connection.id } ?? connection
                            preferences.lastSource = "webdav"
                            useWebDAV(saved)
                            openServerRoot()
                        },
                        onUseSynology: { connection in
                            Task {
                                await useSynology(connection)
                                guard networkBrowser.isConnected else { return }
                                openServerRoot()
                            }
                        },
                        onConnectedSynology: { connection, password, session, sharePath in
                            synologyConnections.save(connection, password: password)
                            preferences.lastSource = "synology:\(connection.id)"
                            networkBrowser.use(synology: connection.name, session: session, rootPath: sharePath)
                            openServerRoot()
                        }
                    )
                    .navigationDestination(for: IOSNetworkFolderRef.self) { folder in
                        IOSNetworkBrowserView(
                            browser: networkBrowser,
                            folder: folder,
                            isRoot: folder.path == networkBrowser.rootPath
                        )
                    }
                    .navigationDestination(for: IOSLibrarySelection.self, destination: destination)
                }
            }

            Tab(L10n.string("ios.navigation.settings"), systemImage: "gearshape", value: IOSTab.settings) {
                NavigationStack {
                    IOSSettingsView(
                        library: library,
                        books: books,
                        onOpenDevice: { selection = .local }
                    )
                }
            }
        }
        .tint(IOSTheme.amber)
        // One ground for the whole app. The lists hide their own so this shows
        // through, which is what stops the darkness shifting between tabs.
        .background(IOSTheme.ground.ignoresSafeArea())
        .environment(artwork)
        .environment(preferences)
        .environment(covers)
        .environment(favorites)
        .environment(readingProgress)
        .task {
            IOSDeviceFolder.prepareIfNeeded()
            await restorePreferredSource()
        }
        // Someone shared a file to Glaze from another app. It lands in the device
        // folder and both shelves are told, because it could be either kind.
        .onOpenURL { url in
            guard IOSIncomingFile.receive(url) else { return }
            books.reload()
            // It landed in the device folder either way; which tab shows it depends
            // only on what kind of file it is.
            selection = MediaFileTypes.isVideo(url) ? .local : .books
        }
        .task { books.reload() }
        // Files land while the app is in the background — the Files app, a cable, a
        // share from somewhere else. Only the device folder is re-read: going back to
        // a NAS every time someone switches apps would be rude and slow.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            books.reload()
        }
    }

    @ViewBuilder
    private func destination(for selection: IOSLibrarySelection) -> some View {
        switch selection {
        case .movie(let item):
            IOSDetailView(item: item, library: library)
        case .series(let show):
            IOSSeriesView(series: show, library: library)
        }
    }

    /// Artwork travels behind the same login as the films, so the loader is told at the
    /// moment the library adopts a connection rather than once at launch.
    private func useWebDAV(_ connection: WebDAVConnection) {
        let password = connections.password(for: connection)
        artwork.use(username: connection.username, password: password)
        networkBrowser.use(webDAV: connection, password: password)
    }

    /// Signs in again with the stored password. The session token DSM hands out does
    /// not survive a relaunch, so coming back to a saved Synology means a fresh login.
    private func useSynology(_ connection: SynologyConnection) async {
        guard let password = synologyConnections.password(for: connection) else {
            library.reportSynologyFailure(SynologyError.badCredentials)
            return
        }
        do {
            let session = try await SynologyClient().logIn(
                to: connection.baseURL,
                account: connection.account,
                password: password
            )
            preferences.lastSource = "synology:\(connection.id)"
            networkBrowser.use(
                synology: connection.name,
                session: session,
                rootPath: connection.libraryPath ?? ""
            )
        } catch {
            library.reportSynologyFailure(error)
        }
    }

    /// Reads whatever is open again, without changing which source that is.
    private func reloadCurrentSource() async {
        switch library.source {
        case .synology(let name):
            if let connection = synologyConnections.connections.first(where: { $0.name == name }) {
                await useSynology(connection)
            }
        case .webDAV(let name):
            if let connection = connections.connections.first(where: { $0.name == name }) {
                useWebDAV(connection)
            }
        case .dlna:
            await discovery.discover()
            if let server = discovery.selectedServer { networkBrowser.use(dlna: server) }
        // The device is no longer one of these — local files are their own tab and
        // read their own folder.
        case .device, .none:
            await restorePreferredSource()
        }
    }

    /// Straight into the folder the viewer chose when they set the server up.
    private func openServerRoot() {
        path = NavigationPath()
        path.append(
            IOSNetworkFolderRef(path: networkBrowser.rootPath, name: networkBrowser.serverName)
        )
    }

    /// Comes back to whatever was open last. Someone who watches films they copied
    /// onto the phone should not have to find them again on every launch.
    private func restorePreferredSource() async {
        connections.reload()

        synologyConnections.reload()
        if let stored = preferences.lastSource, stored.hasPrefix("synology:") {
            let id = String(stored.dropFirst("synology:".count))
            if let connection = synologyConnections.connections.first(where: { $0.id == id }) {
                await useSynology(connection)
                return
            }
        }
        if let connection = synologyConnections.connections.first {
            await useSynology(connection)
            return
        }

        if let connection = connections.connections.first {
            preferences.lastSource = "webdav"
            useWebDAV(connection)
            return
        }

        await discovery.discoverIfNeeded()
        if let server = discovery.selectedServer {
            preferences.lastSource = "dlna"
            networkBrowser.use(dlna: server)
        }
    }

}

