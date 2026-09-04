import Foundation

/// What a metadata service knows about one film.
///
/// Deliberately not shaped like any one provider's JSON. TMDB is what this ships with,
/// but the licence terms around commercial use are not settled (`docs/23`), so the day
/// the provider has to change should be a day of writing one new type, not of touching
/// every screen.
public struct MediaMetadataMatch: Equatable, Sendable, Codable {
    public let providerID: String
    /// The title in the viewer's language, which is the whole point of doing this.
    public let title: String
    /// What the film is called where it was made. Kept because it is often the name
    /// people recognise, and because the release filename is usually built from it.
    public let originalTitle: String?
    /// Other names this film goes by, used only for matching a filename against it.
    ///
    /// A Korean film's original title is Korean and its localised title is Korean, so
    /// neither is the name a release group put in the filename. Without the
    /// international title here, `Parasite.2019.mkv` does not match 기생충 at all.
    public let matchingTitles: [String]
    public let year: Int?
    public let overview: String?
    /// Fetched separately — the provider gives a path, not a file.
    public let posterURL: URL?
    public let backdropURL: URL?
    /// Out of 10, as every provider reports it.
    public let rating: Double?
    public let genres: [String]
    /// How widely known the film is. Only ever a tiebreaker: when a filename matches
    /// two films equally well, the one everybody means is the better guess.
    public let popularity: Double?
    public let voteCount: Int?
    public let externalIDs: MediaExternalIDs

    public init(
        providerID: String,
        title: String,
        originalTitle: String? = nil,
        matchingTitles: [String] = [],
        year: Int? = nil,
        overview: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        rating: Double? = nil,
        genres: [String] = [],
        popularity: Double? = nil,
        voteCount: Int? = nil,
        externalIDs: MediaExternalIDs = MediaExternalIDs()
    ) {
        self.providerID = providerID
        self.title = title
        self.originalTitle = originalTitle
        self.matchingTitles = matchingTitles
        self.year = year
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.rating = rating
        self.genres = genres
        self.popularity = popularity
        self.voteCount = voteCount
        self.externalIDs = externalIDs
    }
}

public enum MetadataProviderError: Error, Sendable, Equatable {
    /// No key configured. Distinguished from a failed lookup because the remedy is
    /// entirely different and the viewer should be told which one they have.
    case notConfigured
    case notFound
    case rateLimited
    case network(String)
}

/// Looks a film up by what little a filename tells us.
public protocol MetadataProviding: Sendable {
    var providerID: String { get }

    /// - Parameter languageCode: what to return the title and overview in.
    /// - Returns: candidates, best first. Empty is a legitimate answer, not an error.
    func search(
        title: String,
        year: Int?,
        languageCode: String
    ) async throws -> [MediaMetadataMatch]

    /// Series are a different index at every provider, and asking the film index for
    /// `The Bear` answers with films called that.
    func searchSeries(
        title: String,
        year: Int?,
        languageCode: String
    ) async throws -> [MediaMetadataMatch]
}

public extension MetadataProviding {
    /// A provider that only knows films is still a usable provider.
    func searchSeries(
        title: String,
        year: Int?,
        languageCode: String
    ) async throws -> [MediaMetadataMatch] { [] }
}

public extension MediaMetadataMatch {
    /// Adds a name this film also goes by, for matching a filename against.
    func addingMatchingTitle(_ title: String) -> MediaMetadataMatch {
        guard !title.isEmpty, title != self.title, !matchingTitles.contains(title) else { return self }
        return MediaMetadataMatch(
            providerID: providerID,
            title: self.title,
            originalTitle: originalTitle,
            matchingTitles: matchingTitles + [title],
            year: year,
            overview: overview,
            posterURL: posterURL,
            backdropURL: backdropURL,
            rating: rating,
            genres: genres,
            popularity: popularity,
            voteCount: voteCount,
            externalIDs: externalIDs
        )
    }
}
