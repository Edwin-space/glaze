import GlazeCore
import SwiftUI

/// Search over the whole library — films, shows, and the episodes inside them.
///
/// tvOS's own search tab brings the keyboard and the layout with it, so this only has
/// to answer the question. The hand-built text field this replaced sat in the sidebar
/// and trapped the focus engine: arrows moved the caret, so focus went in and could not
/// come back out.
struct TVSearchView: View {
    let library: TVLibraryModel
    let onSelect: (TVLibrarySelection) -> Void

    @State private var query = ""

    private let columns = Array(repeating: GridItem(.fixed(220), spacing: 40), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if trimmedQuery.isEmpty {
                    message(
                        symbol: "magnifyingglass",
                        title: L10n.string("tv.search.start"),
                        detail: L10n.string("tv.search.start.detail")
                    )
                } else if matchedSeries.isEmpty, matchedMovies.isEmpty {
                    message(
                        symbol: "film.stack",
                        title: L10n.string("tv.search.empty"),
                        detail: L10n.string("tv.search.empty.detail")
                    )
                } else {
                    Text(
                        String(
                            format: L10n.string("tv.search.results_format"),
                            matchedSeries.count + matchedMovies.count
                        )
                    )
                    .font(.system(size: 32, weight: .semibold))

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
                        ForEach(matchedSeries) { show in
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

                        ForEach(matchedMovies) { movie in
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
            }
            .padding(.horizontal, 76)
            .padding(.top, 40)
            .padding(.bottom, 90)
        }
        .searchable(text: $query, prompt: L10n.string("tv.search.placeholder"))
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A show matches on its own name; a film on its title, its original title and the
    /// filename, because people search for what they remember, which is often neither
    /// of the first two.
    private var matchedSeries: [MediaLibrarySeries] {
        guard !trimmedQuery.isEmpty else { return [] }
        return library.library.series.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var matchedMovies: [MediaLibraryItem] {
        guard !trimmedQuery.isEmpty else { return [] }
        return library.library.movies.filter { movie in
            movie.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
                || movie.sourceName.localizedCaseInsensitiveContains(trimmedQuery)
                || (movie.metadata?.originalTitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 62))
                .foregroundStyle(TVTheme.dim)
            Text(title).font(.system(size: 32, weight: .semibold))
            Text(detail)
                .font(.system(size: 23))
                .foregroundStyle(TVTheme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}
