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

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26, pinnedViews: []) {
                if library.library.isEmpty {
                    status
                } else {
                    if !resumable.isEmpty {
                        section(L10n.string("tv.home.continue"), items: resumable, showsProgress: true)
                    }
                    if !library.library.series.isEmpty {
                        seriesSection(L10n.string("tv.home.series"))
                    }
                    if !library.library.movies.isEmpty {
                        section(L10n.string("tv.home.movies"), items: library.library.movies)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(IOSTheme.ground)
        .navigationTitle(sourceName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(
        _ title: String,
        items: [MediaLibraryItem],
        showsProgress: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
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

    private func seriesSection(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(library.library.series) { show in
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
        VStack(spacing: 12) {
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
        case .dlna(let name), .webDAV(let name): name
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

enum IOSLibrarySelection: Identifiable, Equatable {
    case movie(MediaLibraryItem)
    case series(MediaLibrarySeries)

    var id: String {
        switch self {
        case .movie(let item): "movie:\(item.id)"
        case .series(let show): "series:\(show.id)"
        }
    }
}
