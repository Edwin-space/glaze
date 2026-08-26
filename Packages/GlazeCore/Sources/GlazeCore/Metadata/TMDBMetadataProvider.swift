import Foundation

/// Looks films up on The Movie Database.
///
/// TMDB rather than IMDb because IMDb has no public API — its data is sold through AWS
/// Data Exchange at enterprise prices (`docs/23`). TMDB is free with attribution, has
/// Korean titles and overviews, and is what the rest of this ecosystem uses.
///
/// Attribution is a condition of use and belongs on screen wherever this data is shown.
public struct TMDBMetadataProvider: MetadataProviding {
    public let providerID = "tmdb"

    /// Sized for a television and a Retina display both; TMDB serves whatever width is
    /// asked for from the same original.
    private static let posterWidth = "w780"
    private static let backdropWidth = "w1280"
    private static let imageBase = URL(string: "https://image.tmdb.org/t/p")!
    private static let apiBase = URL(string: "https://api.themoviedb.org/3")!

    private let apiKey: String?
    private let session: URLSession

    public init(apiKey: String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func search(
        title: String,
        year: Int?,
        languageCode: String
    ) async throws -> [MediaMetadataMatch] {
        guard let apiKey, !apiKey.isEmpty else { throw MetadataProviderError.notConfigured }

        var components = URLComponents(
            url: Self.apiBase.appendingPathComponent("search/movie"),
            resolvingAgainstBaseURL: false
        )!
        var items = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "language", value: languageCode),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        // A year narrows a search dramatically and the filename usually has one.
        if let year {
            items.append(URLQueryItem(name: "primary_release_year", value: String(year)))
        }
        components.queryItems = items

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch {
            throw MetadataProviderError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 401: throw MetadataProviderError.notConfigured
            case 429: throw MetadataProviderError.rateLimited
            default: throw MetadataProviderError.network("HTTP \(http.statusCode)")
            }
        }

        return try Self.decode(data, providerID: providerID)
    }

    /// Separated from the request so the shape of TMDB's JSON can be tested against
    /// recorded responses without a key or a network.
    static func decode(_ data: Data, providerID: String) throws -> [MediaMetadataMatch] {
        let decoded: SearchResponse
        do {
            decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw MetadataProviderError.network("unreadable response")
        }

        return decoded.results.map { result in
            MediaMetadataMatch(
                providerID: providerID,
                title: result.title,
                originalTitle: result.original_title,
                year: result.release_date.flatMap(Self.year(from:)),
                overview: result.overview?.nilIfBlank,
                posterURL: result.poster_path.map { imageURL(posterWidth, $0) },
                backdropURL: result.backdrop_path.map { imageURL(backdropWidth, $0) },
                rating: result.vote_average,
                genres: [],
                externalIDs: MediaExternalIDs(tmdbID: String(result.id))
            )
        }
    }

    private static func imageURL(_ width: String, _ path: String) -> URL {
        imageBase.appendingPathComponent(width).appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    /// TMDB dates are `YYYY-MM-DD`, and are sometimes an empty string for a film with
    /// no announced release.
    private static func year(from releaseDate: String) -> Int? {
        Int(releaseDate.prefix(4))
    }

    private struct SearchResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let id: Int
        let title: String
        let original_title: String?
        let overview: String?
        let release_date: String?
        let poster_path: String?
        let backdrop_path: String?
        let vote_average: Double?
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
