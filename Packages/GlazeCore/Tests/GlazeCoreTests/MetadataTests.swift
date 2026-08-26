import Foundation
import Testing
@testable import GlazeCore

/// Shaped like a real TMDB search response, including the fields that are routinely
/// absent or empty on real records.
struct TMDBDecodingTests {
    private let json = """
    {"page":1,"results":[
      {"id":76600,"title":"아바타: 불과 재","original_title":"Avatar: Fire and Ash",
       "overview":"판도라에서의 이야기가 이어진다.","release_date":"2025-12-17",
       "poster_path":"/abc123.jpg","backdrop_path":"/def456.jpg","vote_average":7.6},
      {"id":999,"title":"제목만 있는 작품","original_title":null,"overview":"",
       "release_date":"","poster_path":null,"backdrop_path":null,"vote_average":0.0}
    ],"total_results":2}
    """

    @Test func readsAMatch() throws {
        let matches = try TMDBMetadataProvider.decode(Data(json.utf8), providerID: "tmdb")
        let first = try #require(matches.first)

        #expect(first.title == "아바타: 불과 재")
        #expect(first.originalTitle == "Avatar: Fire and Ash")
        #expect(first.year == 2025)
        #expect(first.externalIDs.tmdbID == "76600")
        #expect(first.rating == 7.6)
    }

    @Test func buildsFullImageURLs() throws {
        let matches = try TMDBMetadataProvider.decode(Data(json.utf8), providerID: "tmdb")
        let first = try #require(matches.first)

        #expect(first.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w780/abc123.jpg")
        #expect(first.backdropURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/def456.jpg")
    }

    /// An unreleased film has an empty release date and no artwork. Reading that as a
    /// year of 0 or a poster URL pointing at nothing would put both on screen.
    @Test func toleratesMissingFields() throws {
        let matches = try TMDBMetadataProvider.decode(Data(json.utf8), providerID: "tmdb")
        let second = try #require(matches.last)

        #expect(second.year == nil)
        #expect(second.overview == nil)
        #expect(second.posterURL == nil)
        #expect(second.originalTitle == nil)
    }

    @Test func reportsAnUnreadableResponse() {
        #expect(throws: MetadataProviderError.network("unreadable response")) {
            try TMDBMetadataProvider.decode(Data("not json".utf8), providerID: "tmdb")
        }
    }

    @Test func refusesToSearchWithNoKey() async {
        let provider = TMDBMetadataProvider(apiKey: nil)
        await #expect(throws: MetadataProviderError.notConfigured) {
            try await provider.search(title: "Avatar", year: 2025, languageCode: "ko")
        }
    }
}

struct MediaSidecarWriterTests {
    private let writer = MediaSidecarWriter()

    private let match = MediaMetadataMatch(
        providerID: "tmdb",
        title: "아바타: 불과 재",
        originalTitle: "Avatar: Fire and Ash",
        year: 2025,
        overview: "판도라의 이야기.",
        rating: 7.6,
        genres: ["SF", "액션"],
        externalIDs: MediaExternalIDs(imdbID: "tt1630029", tmdbID: "76600")
    )

    @Test func writesTheFieldsKodiReads() {
        let nfo = writer.nfo(for: match)

        #expect(nfo.contains("<title>아바타: 불과 재</title>"))
        #expect(nfo.contains("<originaltitle>Avatar: Fire and Ash</originaltitle>"))
        #expect(nfo.contains("<year>2025</year>"))
        #expect(nfo.contains("<rating>7.6</rating>"))
        #expect(nfo.contains("<uniqueid type=\"tmdb\">76600</uniqueid>"))
        #expect(nfo.contains("<uniqueid type=\"imdb\" default=\"true\">tt1630029</uniqueid>"))
        #expect(nfo.contains("<genre>SF</genre>"))
    }

    /// A scraper treats an empty element as a known-empty value, which is worse than
    /// leaving it out and letting it look elsewhere.
    @Test func leavesOutWhatItDoesNotKnow() {
        let sparse = MediaMetadataMatch(providerID: "tmdb", title: "제목만")
        let nfo = writer.nfo(for: sparse)

        #expect(!nfo.contains("<plot>"))
        #expect(!nfo.contains("<year>"))
        #expect(!nfo.contains("<rating>"))
        #expect(!nfo.contains("<originaltitle>"))
    }

    /// An unescaped ampersand makes the whole file unreadable, not one field wrong.
    @Test func escapesCharactersThatWouldBreakTheXML() {
        let awkward = MediaMetadataMatch(
            providerID: "tmdb",
            title: "Tom & Jerry <\"quoted\">",
            overview: "a & b"
        )
        let nfo = writer.nfo(for: awkward)

        #expect(nfo.contains("Tom &amp; Jerry &lt;&quot;quoted&quot;&gt;"))
        #expect(!nfo.contains("Tom & Jerry"))
    }

    @Test func writesBothFilesBesideTheVideo() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glaze-sidecar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let video = directory.appendingPathComponent("Avatar.2025.mkv")
        FileManager.default.createFile(atPath: video.path, contents: Data())

        let written = try writer.write(match, poster: Data("jpeg".utf8), besideVideoAt: video)

        #expect(written.map(\.lastPathComponent).sorted() == ["Avatar.2025-poster.jpg", "Avatar.2025.nfo"])
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Avatar.2025.nfo").path))
    }

    @Test func refusesAStreamedVideo() {
        let streamed = URL(string: "http://nas.local/80.mkv")!
        #expect(throws: MediaSidecarWriter.WriteError.notALocalFile) {
            try writer.write(match, poster: nil, besideVideoAt: streamed)
        }
    }
}
