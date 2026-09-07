import GlazeCore
import SwiftUI

/// A tab bar, because that is what a phone app is.
///
/// iPad gets the same thing: SwiftUI turns a `TabView` into a sidebar there when the
/// window is wide enough, which is the layout an iPad wants without a second code path.
struct IOSRootView: View {
    @State private var discovery = NetworkMediaBrowserModel()
    @State private var library = IOSLibraryModel()
    @State private var artwork = IOSArtworkLoader()
    @State private var connections = WebDAVConnectionStore()
    @State private var synologyConnections = SynologyConnectionStore()
    @State private var preferences = IOSUserPreferences()
    @State private var selection: IOSTab = .library
    @State private var path = NavigationPath()

    private enum IOSTab: Hashable {
        case library
        case sources
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(L10n.string("tv.navigation.library"), systemImage: "rectangle.stack", value: IOSTab.library) {
                NavigationStack(path: $path) {
                    IOSLibraryView(
                        library: library,
                        onOpenSources: { selection = .sources },
                        onSelect: { path.append($0) }
                    )
                    .navigationDestination(for: IOSLibrarySelection.self, destination: destination)
                }
            }

            Tab(L10n.string("tv.navigation.sources"), systemImage: "externaldrive", value: IOSTab.sources) {
                NavigationStack {
                    IOSSourcesView(
                        discovery: discovery,
                        connections: connections,
                        synologyConnections: synologyConnections,
                        library: library,
                        onUseDevice: {
                            useDevice()
                            path = NavigationPath()
                            selection = .library
                        },
                        onUseDLNA: { server in
                            Task {
                                await discovery.select(server)
                                preferences.lastSource = "dlna"
                                library.adopt(
                                    dlnaNodes: discovery.homeNodes,
                                    serverName: server.friendlyName
                                )
                                path = NavigationPath()
                                selection = .library
                            }
                        },
                        onUseWebDAV: { connection in
                            connections.reload()
                            let saved = connections.connections.first { $0.id == connection.id } ?? connection
                            preferences.lastSource = "webdav"
                            useWebDAV(saved)
                            path = NavigationPath()
                            selection = .library
                        },
                        onUseSynology: { connection in
                            Task {
                                await useSynology(connection)
                                path = NavigationPath()
                                selection = .library
                            }
                        },
                        onConnectedSynology: { connection, password, session, sharePath in
                            synologyConnections.save(connection, password: password)
                            preferences.lastSource = "synology:\(connection.id)"
                            library.loadSynology(
                                name: connection.name,
                                session: session,
                                path: sharePath
                            )
                            path = NavigationPath()
                            selection = .library
                        }
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
        .task { await restorePreferredSource() }
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
        library.load(connection, password: password)
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
            library.loadSynology(
                name: connection.name,
                session: session,
                path: connection.libraryPath ?? "/"
            )
        } catch {
            library.reportSynologyFailure(error)
        }
    }

    private func useDevice() {
        preferences.lastSource = "device"
        // Nothing on the device is behind a login, and leaving stale NAS credentials
        // in the loader would send them to a file:// URL.
        artwork.use(username: "", password: nil)
        library.loadDevice()
    }

    /// Comes back to whatever was open last. Someone who watches films they copied
    /// onto the phone should not have to find them again on every launch.
    private func restorePreferredSource() async {
        connections.reload()

        if preferences.lastSource == "device" {
            useDevice()
            return
        }

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

        // No server has ever been set up, but there may be films sitting on the
        // device already — copied over a cable, most likely.
        if hasFilmsOnDevice {
            useDevice()
            return
        }

        await discovery.discoverIfNeeded()
        if let server = discovery.selectedServer, !discovery.homeNodes.isEmpty {
            preferences.lastSource = "dlna"
            library.adopt(dlnaNodes: discovery.homeNodes, serverName: server.friendlyName)
        }
    }

    private var hasFilmsOnDevice: Bool {
        let root = IOSLibraryModel.deviceLibraryURL
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let url as URL in walker where MediaFileTypes.isVideo(url) {
            return true
        }
        return false
    }
}
