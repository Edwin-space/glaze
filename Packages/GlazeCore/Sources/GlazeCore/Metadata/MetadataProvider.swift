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
    public let year: Int?
    public let overview: String?
    /// Fetched separately — the provider gives a path, not a file.
    public let posterURL: URL?
    public let backdropURL: URL?
    /// Out of 10, as every provider reports it.
    public let rating: Double?
    public let genres: [String]
    public let externalIDs: MediaExternalIDs

    public init(
        providerID: String,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        rating: Double? = nil,
        genres: [String] = [],
        externalIDs: MediaExternalIDs = MediaExternalIDs()
    ) {
        self.providerID = providerID
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.rating = rating
        self.genres = genres
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
}
