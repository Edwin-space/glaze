import GlazeCore
import SwiftUI

/// The launch surface, shaped like the Apple TV app's Home: one thing held up large,
/// then shelves under it.
///
/// What is on the shelves is the difference from before. A folder of files is now a
/// library — films, shows with their episodes inside them, and the genres that were
/// actually scraped — so a viewer sees what they own rather than what the release
/// groups named it.
struct TVHomeView: View {
    let library: TVLibraryModel
    @Bindable var preferences: TVUserPreferences
    let onOpenSources: () -> Void
    let onSelect: (TVLibrarySelection) -> Void

    @Environment(TVArtworkLoader.self) private var artwork
    @State private var positions = PlaybackPositionStore()

    var body: some View {
        ZStack(alignment: .top) {
            backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    hero.frame(height: 470)

                    if !resumable.isEmpty {
                        itemShelf(L10n.string("tv.home.continue"), items: resumable, showsProgress: true)
                    }

                    if !library.library.recentlyAdded.isEmpty {
                        entryShelf(L10n.string("tv.home.recent"), entries: library.library.recentlyAdded)
                    }

                    if !library.library.series.isEmpty {
                        seriesShelf(L10n.string("tv.home.series"), series: library.library.series)
                    }

                    if !library.library.movies.isEmpty {
                        itemShelf(L10n.string("tv.home.movies"), items: library.library.movies)
                    }

                    ForEach(library.library.genres.prefix(4)) { genre in
                        genreShelf(genre)
                    }

                    if library.library.isEmpty {
                        statusPanel
                    }
                }
                .padding(.bottom, 90)
            }
        }
    }

    // MARK: - Hero

    /// The featured poster stands in for the fanart Apple has and a NAS does not. Blurred
    /// hard and pushed dark, it reads as the film's own colour rather than as a picture.
    private var backdrop: some View {
        ZStack {
            if let image = artworkImage(for: featured) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60)
                    .opacity(0.5)
            } else {
                TVTheme.signature(for: featured?.displayTitle ?? "Glaze")
            }

            LinearGradient(
                colors: [TVTheme.ground.opacity(0.2), TVTheme.ground.opacity(0.85), TVTheme.ground],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 700)
        .clipped()
        .ignoresSafeArea()
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 46) {
            VStack(alignment: .leading, spacing: 18) {
                Spacer()

                Text(featured?.displayTitle ?? L10n.string("tv.home.welcome.title"))
                    .font(.system(size: 60, weight: .bold))
                    .lineLimit(2)
                    .frame(maxWidth: 940, alignment: .leading)

                if let featured {
                    metadataLine(for: featured)
                }

                Text(heroDetail)
                    .font(.system(size: 25))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
                    .frame(maxWidth: 900, alignment: .leading)

                heroActions
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 76)
    }

    @ViewBuilder
    private var heroActions: some View {
        if let featured {
            HStack(spacing: 20) {
                Button {
                    onSelect(.movie(featured))
                } label: {
                    Label(
                        resumeTime(for: featured) == nil
                            ? L10n.string("tv.detail.play")
                            : L10n.string("tv.detail.resume"),
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
            .padding(.top, 10)
        } else {
            Button(action: onOpenSources) {
                Label(L10n.string("tv.home.connect"), systemImage: "externaldrive.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .padding(.top, 10)
        }
    }

    private func metadataLine(for item: MediaLibraryItem) -> some View {
        HStack(spacing: 12) {
            if let year = item.year {
                Text(String(year))
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let rating = item.rating, rating > 0 {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(TVTheme.amber)
                    .labelStyle(.titleAndIcon)
            }
            ForEach(item.genres.prefix(3), id: \.self) { genre in
                TVChip(text: genre)
            }
            ForEach(item.parsed.badges.prefix(2), id: \.self) { badge in
                TVChip(text: badge, emphasized: badge == "4K")
            }
        }
    }

    // MARK: - Shelves

    private func itemShelf(
        _ title: String,
        items: [MediaLibraryItem],
        showsProgress: Bool = false
    ) -> some View {
        TVShelf(title: title) {
            ForEach(items) { item in
                Button { onSelect(.movie(item)) } label: {
                    TVPosterCard(
                        title: item.displayTitle,
                        subtitle: subtitle(for: item),
                        posterURL: item.posterURL,
                        badges: item.parsed.badges,
                        progress: showsProgress ? progress(for: item) : nil
                    )
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// Films and shows on one shelf, each opening the screen that suits it.
    private func entryShelf(_ title: String, entries: [MediaLibraryEntry]) -> some View {
        TVShelf(title: title) {
            ForEach(entries) { entry in
                switch entry {
                case .movie(let item):
                    Button { onSelect(.movie(item)) } label: {
                        TVPosterCard(
                            title: item.displayTitle,
                            subtitle: subtitle(for: item),
                            posterURL: item.posterURL,
                            badges: item.parsed.badges
                        )
                    }
                    .buttonStyle(.borderless)
                case .series(let show):
                    Button { onSelect(.series(show)) } label: {
                        TVPosterCard(
                            title: show.title,
                            subtitle: String(
                                format: L10n.string("tv.library.episode_count_format"),
                                show.episodeCount
                            ),
                            posterURL: show.posterURL
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func seriesShelf(_ title: String, series: [MediaLibrarySeries]) -> some View {
        TVShelf(title: title) {
            ForEach(series) { show in
                Button { onSelect(.series(show)) } label: {
                    TVPosterCard(
                        title: show.title,
                        subtitle: String(
                            format: L10n.string("tv.library.episode_count_format"),
                            show.episodeCount
                        ),
                        posterURL: show.posterURL
                    )
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func genreShelf(_ genre: MediaLibraryGenre) -> some View {
        TVShelf(title: genre.name) {
            ForEach(genre.series) { show in
                Button { onSelect(.series(show)) } label: {
                    TVPosterCard(title: show.title, subtitle: nil, posterURL: show.posterURL)
                }
                .buttonStyle(.borderless)
            }
            ForEach(genre.movies) { movie in
                Button { onSelect(.movie(movie)) } label: {
                    TVPosterCard(
                        title: movie.displayTitle,
                        subtitle: movie.year.map(String.init),
                        posterURL: movie.posterURL
                    )
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var statusPanel: some View {
        HStack(spacing: 24) {
            if library.isLoading {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: "film.stack")
                    .font(.system(size: 42))
                    .foregroundStyle(TVTheme.dim)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("tv.home.library.title"))
                    .font(.system(size: 31, weight: .semibold))
                Text(statusDetail)
                    .font(.system(size: 22))
                    .foregroundStyle(TVTheme.dim)
            }

            Spacer()

            if case .failed = library.phase {
                Button(L10n.string("tv.home.connect"), action: onOpenSources)
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: 1000, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 76)
    }

    private var statusDetail: String {
        switch library.phase {
        case .loading(let foldersRead):
            foldersRead == 0
                ? L10n.string("tv.home.library.loading")
                : String(format: L10n.string("tv.home.library.scanning_format"), foldersRead)
        case .failed(let message): message
        case .ready: L10n.string("tv.home.library.empty")
        case .idle: L10n.string("tv.home.connect.detail")
        }
    }

    // MARK: - Data

    private func artworkImage(for item: MediaLibraryItem?) -> Image? {
        guard let posterURL = item?.posterURL else { return nil }
        artwork.loadIfNeeded(posterURL)
        return artwork.image(for: posterURL)
    }

    private var resumable: [MediaLibraryItem] {
        allItems.filter { positions.position(for: playbackKey(for: $0)) != nil }
    }

    private var allItems: [MediaLibraryItem] {
        library.library.movies + library.library.series.flatMap(\.allEpisodes)
    }

    private var featured: MediaLibraryItem? {
        if let resumed = resumable.first { return resumed }
        for entry in library.library.recentlyAdded {
            if case .movie(let item) = entry { return item }
        }
        return library.library.movies.first
            ?? library.library.series.first?.allEpisodes.first
    }

    private var heroDetail: String {
        if let featured, let plot = featured.plot, !plot.isEmpty { return plot }
        switch library.source {
        case .dlna(let name), .webDAV(let name), .synology(let name):
            return String(format: L10n.string("tv.home.source.detail_format"), name)
        case .none:
            return L10n.string("tv.home.welcome.detail")
        }
    }

    private func subtitle(for item: MediaLibraryItem) -> String? {
        if let label = item.episodeLabel { return label }
        return item.year.map(String.init)
    }

    private func playbackKey(for item: MediaLibraryItem) -> MediaResource {
        guard let resource = library.resource(for: item) else {
            return .localFile(item.playbackURL)
        }
        return .network(resource)
    }

    private func resumeTime(for item: MediaLibraryItem) -> TimeInterval? {
        positions.position(for: playbackKey(for: item))
    }

    private func progress(for item: MediaLibraryItem) -> Double? {
        guard let time = resumeTime(for: item), let duration = item.duration, duration > 0 else {
            return nil
        }
        return time / duration
    }
}

/// What the viewer picked, in a form every screen can route on.
enum TVLibrarySelection: Equatable {
    case movie(MediaLibraryItem)
    case series(MediaLibrarySeries)
}
