import GlazeCore
import SwiftUI

struct TVRootView: View {
    @State private var preferences = TVUserPreferences()
    @State private var media = NetworkMediaBrowserModel()
    @State private var library = TVLibraryModel()
    @State private var artwork = TVArtworkLoader()
    @State private var connections = TVWebDAVConnections()

    var body: some View {
        Group {
            if preferences.onboardingCompleted {
                TVAppShell(
                    media: media,
                    library: library,
                    connections: connections,
                    preferences: preferences
                )
            } else {
                TVOnboardingView(model: media, preferences: preferences)
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
    @Bindable var preferences: TVUserPreferences

    @Environment(TVArtworkLoader.self) private var artwork
    @State private var selection: TVTab = .home
    @State private var route: TVLibrarySelection?

    var body: some View {
        TabView(selection: $selection) {
            Tab(L10n.string("tv.navigation.home"), systemImage: "house.fill", value: TVTab.home) {
                TVHomeView(
                    library: library,
                    preferences: preferences,
                    onOpenSources: { selection = .sources },
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
                    onUseWebDAV: { connection in
                        connections.reload()
                        useWebDAV(connection)
                        selection = .home
                    }
                )
            }

            Tab(L10n.string("settings.title"), systemImage: "gearshape.fill", value: TVTab.settings) {
                TVSettingsView(preferences: preferences)
            }

            Tab(value: TVTab.search, role: .search) {
                TVSearchView(library: library, onSelect: { route = $0 })
            }
        }
        .background(TVTheme.ground.ignoresSafeArea())
        .task(id: preferences.preferredServerID) {
            await loadPreferredSource()
        }
        .onChange(of: media.homeNodes.count) { _, _ in
            adoptDLNAIfNeeded()
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
            useWebDAV(connection)
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
    }

    private func adoptDLNAIfNeeded() {
        guard connections.connections.isEmpty, !media.homeNodes.isEmpty else { return }
        library.adopt(
            dlnaNodes: media.homeNodes,
            serverName: media.selectedServer?.friendlyName ?? ""
        )
    }
}

private enum TVTab: Hashable {
    case home
    case movies
    case series
    case sources
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
