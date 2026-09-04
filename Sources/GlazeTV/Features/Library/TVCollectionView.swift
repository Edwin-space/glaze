import GlazeCore
import SwiftUI

/// Everything of one kind, as a grid of posters.
///
/// A shelf shows what is worth surfacing; this is where a viewer goes when they know
/// what they are looking for and want to see all of it at once.
struct TVCollectionView: View {
    let title: String
    let movies: [MediaLibraryItem]
    let series: [MediaLibrarySeries]
    let onSelect: (TVLibrarySelection) -> Void

    private let columns = Array(repeating: GridItem(.fixed(220), spacing: 40), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(title)
                        .font(.system(size: 44, weight: .bold))
                    Text(String(format: L10n.string("tv.library.count_format"), count))
                        .font(.system(size: 24))
                        .foregroundStyle(TVTheme.dim)
                }

                if count == 0 {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
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

                        ForEach(movies) { movie in
                            Button { onSelect(.movie(movie)) } label: {
                                TVPosterCard(
                                    title: movie.displayTitle,
                                    subtitle: movie.year.map(String.init),
                                    posterURL: movie.posterURL,
                                    badges: movie.parsed.badges
                                )
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .padding(.horizontal, 76)
            .padding(.top, 40)
            .padding(.bottom, 90)
        }
    }

    private var count: Int { movies.count + series.count }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 52))
                .foregroundStyle(TVTheme.dim)
            Text(L10n.string("tv.library.empty"))
                .font(.system(size: 27))
                .foregroundStyle(TVTheme.dim)
        }
        .padding(.top, 80)
    }
}
