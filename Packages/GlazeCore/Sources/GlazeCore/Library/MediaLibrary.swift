import Foundation

/// One playable thing, with everything the shelves need already resolved.
///
/// Named `MediaLibraryItem` rather than `MediaLibraryItem` because SwiftUI pulls in
/// `DeveloperToolsSupport`, which declares a `MediaLibraryItem` of its own; the plain name
/// is ambiguous in every view file.
///
/// Built once when a folder is read, because a television redraws a shelf on every
/// focus change and re-parsing a release name forty times per movement is visible.
public struct MediaLibraryItem: Identifiable, Equatable, Sendable {
    public let id: String
    /// What the server called it — the filename, kept for the info panel.
    public let sourceName: String
    public let parsed: ParsedMediaTitle
    public let metadata: MediaNFO?
    public let posterURL: URL?
    public let playbackURL: URL
    public let subtitleURLs: [URL]
    public let dateAdded: Date?
    public let byteCount: Int64?
    public let duration: TimeInterval?

    public init(
        id: String,
        sourceName: String,
        parsed: ParsedMediaTitle,
        metadata: MediaNFO? = nil,
        posterURL: URL? = nil,
        playbackURL: URL,
        subtitleURLs: [URL] = [],
        dateAdded: Date? = nil,
        byteCount: Int64? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.sourceName = sourceName
        self.parsed = parsed
        self.metadata = metadata
        self.posterURL = posterURL
        self.playbackURL = playbackURL
        self.subtitleURLs = subtitleURLs
        self.dateAdded = dateAdded
        self.byteCount = byteCount
        self.duration = duration
    }

    /// The NFO wins over the filename: it holds the title in the viewer's language,
    /// which is the entire reason the Mac fetches and writes one.
    public var displayTitle: String {
        if let title = metadata?.title, !title.isEmpty { return title }
        return parsed.title
    }

    public var year: Int? { metadata?.year ?? parsed.year }
    public var plot: String? { metadata?.plot }
    public var genres: [String] { metadata?.genres ?? [] }
    public var rating: Double? { metadata?.rating }

    public var seasonNumber: Int? { metadata?.season ?? parsed.season }
    public var episodeNumber: Int? { metadata?.episode ?? parsed.episode }

    /// An episode is anything that says which season or episode it is. A film never
    /// does, so the absence is as reliable as the presence.
    public var isEpisode: Bool {
        if metadata?.kind == .episode { return true }
        if metadata?.kind == .movie { return false }
        return seasonNumber != nil || episodeNumber != nil
    }

    /// What the episode belongs to. The NFO says outright; otherwise the release name
    /// before `S01E02` is the show.
    public var showTitle: String? {
        guard isEpisode else { return nil }
        if let showTitle = metadata?.showTitle, !showTitle.isEmpty { return showTitle }
        return parsed.title.isEmpty ? nil : parsed.title
    }

    /// What to call the episode in a list. The scraped title first, then whatever the
    /// release name called it, and only then the filename.
    public var episodeDisplayTitle: String {
        if let title = metadata?.title, !title.isEmpty { return title }
        if let title = parsed.episodeTitle, !title.isEmpty { return title }
        return sourceName
    }

    /// A label for the episode itself, e.g. `S01E03`.
    public var episodeLabel: String? {
        guard let season = seasonNumber else {
            return episodeNumber.map { String(format: "E%02d", $0) }
        }
        guard let episode = episodeNumber else { return String(format: "S%02d", season) }
        return String(format: "S%02dE%02d", season, episode)
    }
}

public struct MediaLibrarySeason: Identifiable, Equatable, Sendable {
    /// Season zero is where specials live, so the number cannot stand in for "unknown";
    /// an episode with no season at all gets -1.
    public let id: Int
    public var number: Int { id }
    public let episodes: [MediaLibraryItem]

    public init(id: Int, episodes: [MediaLibraryItem]) {
        self.id = id
        self.episodes = episodes
    }
}

public struct MediaLibrarySeries: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let posterURL: URL?
    public let seasons: [MediaLibrarySeason]
    public let genres: [String]
    public let plot: String?
    public let year: Int?
    public let dateAdded: Date?

    public var episodeCount: Int { seasons.reduce(0) { $0 + $1.episodes.count } }
    public var allEpisodes: [MediaLibraryItem] { seasons.flatMap(\.episodes) }

    public init(
        id: String,
        title: String,
        posterURL: URL?,
        seasons: [MediaLibrarySeason],
        genres: [String] = [],
        plot: String? = nil,
        year: Int? = nil,
        dateAdded: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.posterURL = posterURL
        self.seasons = seasons
        self.genres = genres
        self.plot = plot
        self.year = year
        self.dateAdded = dateAdded
    }
}

/// A film, or a show — what a shelf holds when it can hold either.
///
/// A "recently added" shelf that listed episodes showed the same series four times in
/// a row. It has to name the show once, which means the shelf's element cannot be an
/// episode.
public enum MediaLibraryEntry: Identifiable, Equatable, Sendable {
    case movie(MediaLibraryItem)
    case series(MediaLibrarySeries)

    public var id: String {
        switch self {
        case .movie(let item): "movie:\(item.id)"
        case .series(let show): "series:\(show.id)"
        }
    }

    public var title: String {
        switch self {
        case .movie(let item): item.displayTitle
        case .series(let show): show.title
        }
    }

    public var posterURL: URL? {
        switch self {
        case .movie(let item): item.posterURL
        case .series(let show): show.posterURL
        }
    }

    public var dateAdded: Date? {
        switch self {
        case .movie(let item): item.dateAdded
        case .series(let show): show.dateAdded
        }
    }
}

/// A folder of files, understood.
public struct MediaLibrary: Equatable, Sendable {
    public let movies: [MediaLibraryItem]
    public let series: [MediaLibrarySeries]
    /// Newest first. A show appears once, dated by its newest episode.
    public let recentlyAdded: [MediaLibraryEntry]
    /// Genre name to the films and shows in it, largest first. Empty when nothing in
    /// the folder has an NFO, which is the honest answer rather than one "기타" bucket.
    public let genres: [MediaLibraryGenre]

    public var isEmpty: Bool { movies.isEmpty && series.isEmpty }

    public init(
        movies: [MediaLibraryItem] = [],
        series: [MediaLibrarySeries] = [],
        recentlyAdded: [MediaLibraryEntry] = [],
        genres: [MediaLibraryGenre] = []
    ) {
        self.movies = movies
        self.series = series
        self.recentlyAdded = recentlyAdded
        self.genres = genres
    }
}

public struct MediaLibraryGenre: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String { id }
    public let movies: [MediaLibraryItem]
    public let series: [MediaLibrarySeries]

    public var count: Int { movies.count + series.count }

    public init(id: String, movies: [MediaLibraryItem], series: [MediaLibrarySeries]) {
        self.id = id
        self.movies = movies
        self.series = series
    }
}
