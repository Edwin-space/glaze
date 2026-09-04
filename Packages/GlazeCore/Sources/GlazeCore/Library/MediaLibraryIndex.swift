import Foundation

/// Turns a flat list of files into something a television can be browsed with.
///
/// A NAS folder is forty files in a row. Apple's own TV app never shows a viewer a row
/// of files: it shows films, and it shows a series once with its episodes inside it.
/// That difference is entirely this type's job.
public enum MediaLibraryIndex {
    public static func build(from items: [MediaLibraryItem]) -> MediaLibrary {
        var movies: [MediaLibraryItem] = []
        var episodesByShow: [String: [MediaLibraryItem]] = [:]
        var showTitles: [String: String] = [:]

        for item in items {
            guard item.isEpisode, let showTitle = item.showTitle else {
                movies.append(item)
                continue
            }
            let key = groupingKey(for: showTitle)
            episodesByShow[key, default: []].append(item)
            // Keep the longest spelling seen: `The Bear` beats `Bear`, and an NFO's
            // title beats a release name that dropped the article.
            if (showTitles[key]?.count ?? 0) < showTitle.count {
                showTitles[key] = showTitle
            }
        }

        let series = episodesByShow.map { key, episodes in
            makeSeries(id: key, title: showTitles[key] ?? key, episodes: episodes)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        movies.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }

        return MediaLibrary(
            movies: movies,
            series: series,
            recentlyAdded: recentlyAdded(movies: movies, series: series),
            genres: genres(movies: movies, series: series)
        )
    }

    private static func makeSeries(
        id: String,
        title: String,
        episodes: [MediaLibraryItem]
    ) -> MediaLibrarySeries {
        var bySeason: [Int: [MediaLibraryItem]] = [:]
        for episode in episodes {
            // An episode that says which one it is but not which season still has to
            // land somewhere; -1 sorts ahead of season 0's specials.
            bySeason[episode.seasonNumber ?? -1, default: []].append(episode)
        }

        let seasons = bySeason
            .map { number, episodes in
                MediaLibrarySeason(
                    id: number,
                    episodes: episodes.sorted { left, right in
                        let leftNumber = left.episodeNumber ?? Int.max
                        let rightNumber = right.episodeNumber ?? Int.max
                        if leftNumber != rightNumber { return leftNumber < rightNumber }
                        return left.sourceName.localizedStandardCompare(right.sourceName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.number < $1.number }

        // A show's own details come from whichever episode was scraped; they agree in
        // practice and any answer beats none.
        let described = episodes.first { $0.metadata != nil } ?? episodes[0]
        return MediaLibrarySeries(
            id: id,
            title: title,
            posterURL: episodes.compactMap(\.posterURL).first,
            seasons: seasons,
            genres: described.genres,
            plot: described.plot,
            year: episodes.compactMap(\.year).min(),
            dateAdded: episodes.compactMap(\.dateAdded).max()
        )
    }

    /// Only files the server actually dated. Sorting the undated ones in by name would
    /// put a shelf together that claims to be recent and is not.
    ///
    /// A show counts once, at the date of its newest episode — four episodes added on
    /// the same evening are one thing that happened, not four.
    private static func recentlyAdded(
        movies: [MediaLibraryItem],
        series: [MediaLibrarySeries],
        limit: Int = 20
    ) -> [MediaLibraryEntry] {
        let entries = movies.map(MediaLibraryEntry.movie) + series.map(MediaLibraryEntry.series)
        return entries
            .filter { $0.dateAdded != nil }
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    private static func genres(movies: [MediaLibraryItem], series: [MediaLibrarySeries]) -> [MediaLibraryGenre] {
        var moviesByGenre: [String: [MediaLibraryItem]] = [:]
        var seriesByGenre: [String: [MediaLibrarySeries]] = [:]

        for movie in movies {
            for genre in movie.genres { moviesByGenre[genre, default: []].append(movie) }
        }
        for show in series {
            for genre in show.genres { seriesByGenre[genre, default: []].append(show) }
        }

        let names = Set(moviesByGenre.keys).union(seriesByGenre.keys)
        return names
            .map { name in
                MediaLibraryGenre(
                    id: name,
                    movies: moviesByGenre[name] ?? [],
                    series: seriesByGenre[name] ?? []
                )
            }
            .sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    /// `The.Bear.S01E01` and `the bear - s01e02` are the same show. Case, punctuation
    /// and the separators release groups use are all noise here.
    ///
    /// An apostrophe is dropped rather than turned into a separator: half the release
    /// groups write `Tom Clancy's Jack Ryan` and half write `Tom Clancys Jack Ryan`,
    /// and splitting on it made those two different shows on the shelf.
    public static func groupingKey(for title: String) -> String {
        let folded = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "[\u{0027}\u{2018}\u{2019}\u{02BC}`]", with: "", options: .regularExpression)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}
