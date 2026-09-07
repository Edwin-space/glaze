import GlazeCore
import SwiftUI

/// The library, as a grid that grows with the screen.
///
/// One layout for both devices: the column count follows the available width, so an
/// iPhone shows three posters across and an iPad shows seven, without two code paths
/// that drift apart.
struct IOSLibraryView: View {
    let library: IOSLibraryModel
    let onOpenSources: () -> Void
    let onSelect: (IOSLibrarySelection) -> Void

    @State private var positions = PlaybackPositionStore()
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: IOSTheme.Spacing.medium)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IOSTheme.Spacing.section, pinnedViews: []) {
                if library.library.isEmpty {
                    status
                } else if isSearching {
                    searchResults
                } else {
                    if !resumable.isEmpty {
                        section(L10n.string("tv.home.continue"), items: resumable, showsProgress: true)
                    }
                    if !library.library.series.isEmpty {
                        seriesSection(L10n.string("tv.home.series"), shows: library.library.series)
                    }
                    if !library.library.movies.isEmpty {
                        section(L10n.string("tv.home.movies"), items: library.library.movies)
                    }
                }
            }
            .padding(.horizontal, IOSTheme.Spacing.medium)
            .padding(.vertical, IOSTheme.Spacing.small)
        }
        .background(IOSTheme.ground)
        .navigationTitle(sourceName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: L10n.string("ios.library.search")
        )
    }

    // MARK: - Search

    /// A library of a hundred films on a phone screen is a lot of scrolling, and the
    /// name is what people remember. Titles are matched as well as file names, so
    /// `기생충` finds `Parasite.2019.1080p.mkv` once the Mac has described it.
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var searchResults: some View {
        let shows = library.library.series.filter { matches($0.title) }
        let films = (library.library.movies + library.library.series.flatMap(\.allEpisodes))
            .filter { matches($0.displayTitle) || matches($0.sourceName) }

        if shows.isEmpty, films.isEmpty {
            Text(L10n.string("ios.library.search.empty"))
                .font(.callout)
                .foregroundStyle(IOSTheme.dim)
                .frame(maxWidth: .infinity)
                // Pushed down the screen rather than spaced: an empty result
                // should sit where the eye lands, not under the search field.
                .padding(.top, 70)
        } else {
            if !shows.isEmpty {
                seriesSection(L10n.string("tv.home.series"), shows: shows)
            }
            if !films.isEmpty {
                section(L10n.string("tv.home.movies"), items: films)
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        text.range(
            of: query.trimmingCharacters(in: .whitespaces),
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private func section(
        _ title: String,
        items: [MediaLibraryItem],
        showsProgress: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.small) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: IOSTheme.Spacing.large) {
                ForEach(items) { item in
                    Button { onSelect(.movie(item)) } label: {
                        IOSPosterCard(
                            title: item.displayTitle,
                            subtitle: subtitle(for: item),
                            posterURL: item.posterURL,
                            badges: item.parsed.badges,
                            progress: showsProgress ? progress(for: item) : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func seriesSection(_ title: String, shows: [MediaLibrarySeries]) -> some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.small) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: IOSTheme.Spacing.large) {
                ForEach(shows) { show in
                    Button { onSelect(.series(show)) } label: {
                        IOSPosterCard(
                            title: show.title,
                            subtitle: String(
                                format: L10n.string("tv.library.episode_count_format"),
                                show.episodeCount
                            ),
                            posterURL: show.posterURL
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        VStack(spacing: IOSTheme.Spacing.small) {
            if library.isLoading {
                ProgressView()
            } else {
                Image(systemName: "film.stack")
                    .font(.largeTitle)
                    .foregroundStyle(IOSTheme.dim)
            }
            Text(statusDetail)
                .font(.callout)
                .foregroundStyle(IOSTheme.dim)
                .multilineTextAlignment(.center)

            if case .idle = library.phase {
                Button(L10n.string("tv.home.connect"), action: onOpenSources)
                    .buttonStyle(.borderedProminent)
                    .tint(IOSTheme.amber)
            }
        }
        .frame(maxWidth: .infinity)
        // Same idea as the empty search: the invitation to connect belongs in
        // the middle of an empty screen, not at the top of it.
        .padding(.top, 80)
    }

    private var statusDetail: String {
        switch library.phase {
        case .loading(let read):
            read == 0
                ? L10n.string("tv.home.library.loading")
                : String(format: L10n.string("tv.home.library.scanning_format"), read)
        case .failed(let message): message
        case .ready: L10n.string("tv.home.library.empty")
        case .idle: L10n.string("tv.home.connect.detail")
        }
    }

    private var sourceName: String {
        switch library.source {
        case .dlna(let name), .webDAV(let name), .synology(let name): name
        case .device: L10n.string("ios.device.title")
        case .none: "Glaze"
        }
    }

    private var resumable: [MediaLibraryItem] {
        let all = library.library.movies + library.library.series.flatMap(\.allEpisodes)
        return all.filter { positions.position(for: key(for: $0)) != nil }
    }

    private func subtitle(for item: MediaLibraryItem) -> String? {
        item.episodeLabel ?? item.year.map(String.init)
    }

    private func key(for item: MediaLibraryItem) -> MediaResource {
        guard let resource = library.resource(for: item) else { return .localFile(item.playbackURL) }
        return .network(resource)
    }

    private func progress(for item: MediaLibraryItem) -> Double? {
        guard let time = positions.position(for: key(for: item)),
              let duration = item.duration, duration > 0 else { return nil }
        return time / duration
    }
}

enum IOSLibrarySelection: Identifiable, Hashable {
    case movie(MediaLibraryItem)
    case series(MediaLibrarySeries)

    var id: String {
        switch self {
        case .movie(let item): "movie:\(item.id)"
        case .series(let show): "series:\(show.id)"
        }
    }

    // The payloads are value types the library rebuilt from a folder listing; their
    // identity is the address they came from, which is what the navigation path needs.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
