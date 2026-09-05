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
    @State private var selection: IOSTab = .library
    @State private var route: IOSLibrarySelection?

    private enum IOSTab: Hashable {
        case library
        case sources
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(L10n.string("tv.navigation.library"), systemImage: "rectangle.stack", value: IOSTab.library) {
                NavigationStack {
                    IOSLibraryView(
                        library: library,
                        onOpenSources: { selection = .sources },
                        onSelect: { route = $0 }
                    )
                }
            }

            Tab(L10n.string("tv.navigation.sources"), systemImage: "externaldrive", value: IOSTab.sources) {
                NavigationStack {
                    IOSSourcesView(
                        discovery: discovery,
                        connections: connections,
                        onUseDLNA: { server in
                            Task {
                                await discovery.select(server)
                                library.adopt(
                                    dlnaNodes: discovery.homeNodes,
                                    serverName: server.friendlyName
                                )
                                selection = .library
                            }
                        },
                        onUseWebDAV: { connection in
                            connections.reload()
                            let saved = connections.connections.first { $0.id == connection.id } ?? connection
                            useWebDAV(saved)
                            selection = .library
                        }
                    )
                }
            }
        }
        .tint(IOSTheme.amber)
        .environment(artwork)
        .task { await restorePreferredSource() }
        .fullScreenCover(item: $route) { selection in
            destination(for: selection)
        }
    }

    @ViewBuilder
    private func destination(for selection: IOSLibrarySelection) -> some View {
        switch selection {
        case .movie(let item):
            if let resource = library.resource(for: item) {
                IOSPlayerView(resource: resource, title: item.displayTitle)
            }
        case .series(let show):
            NavigationStack {
                IOSSeriesView(series: show, library: library)
            }
        }
    }

    /// Artwork travels behind the same login as the films, so the loader is told at the
    /// moment the library adopts a connection rather than once at launch.
    private func useWebDAV(_ connection: WebDAVConnection) {
        let password = connections.password(for: connection)
        artwork.use(username: connection.username, password: password)
        library.load(connection, password: password)
    }

    private func restorePreferredSource() async {
        connections.reload()
        if let connection = connections.connections.first {
            useWebDAV(connection)
            return
        }
        await discovery.discoverIfNeeded()
        if let server = discovery.selectedServer, !discovery.homeNodes.isEmpty {
            library.adopt(dlnaNodes: discovery.homeNodes, serverName: server.friendlyName)
        }
    }
}
