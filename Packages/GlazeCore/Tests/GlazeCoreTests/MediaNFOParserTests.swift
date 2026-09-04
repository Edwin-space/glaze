import Foundation
import Testing
@testable import GlazeCore

@Suite struct MediaNFOParserTests {
    /// The exact shape the Mac writes, so the two halves of the product cannot drift
    /// apart without a test noticing.
    @Test func readsBackWhatTheMacWrites() throws {
        let match = MediaMetadataMatch(
            providerID: "tmdb",
            title: "기생충",
            originalTitle: "Parasite",
            year: 2019,
            overview: "반지하에 사는 가족이 언덕 위 저택에 발을 들인다.",
            rating: 8.5,
            genres: ["드라마", "스릴러"],
            externalIDs: MediaExternalIDs(imdbID: "tt6751668", tmdbID: "496243")
        )
        let text = MediaSidecarWriter().nfo(for: match)

        let nfo = try #require(MediaNFOParser.parse(Data(text.utf8)))
        #expect(nfo.kind == .movie)
        #expect(nfo.title == "기생충")
        #expect(nfo.originalTitle == "Parasite")
        #expect(nfo.year == 2019)
        #expect(nfo.plot == match.overview)
        #expect(nfo.rating == 8.5)
        #expect(nfo.genres == ["드라마", "스릴러"])
        #expect(nfo.externalIDs.tmdbID == "496243")
        #expect(nfo.externalIDs.imdbID == "tt6751668")
    }

    @Test func readsAnEpisodeWrittenByKodi() throws {
        let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <episodedetails>
          <title>System Crasher</title>
          <showtitle>The Bear</showtitle>
          <season>2</season>
          <episode>7</episode>
          <plot>Carmy tries to open on time.</plot>
          <runtime>44</runtime>
          <premiered>2023-06-22</premiered>
          <actor><name>Jeremy Allen White</name><role>Carmy</role></actor>
        </episodedetails>
        """
        let nfo = try #require(MediaNFOParser.parse(Data(text.utf8)))
        #expect(nfo.kind == .episode)
        #expect(nfo.title == "System Crasher")
        #expect(nfo.showTitle == "The Bear")
        #expect(nfo.season == 2)
        #expect(nfo.episode == 7)
        #expect(nfo.runtimeMinutes == 44)
        // The year is not stated; the air date carries it.
        #expect(nfo.year == 2023)
    }

    /// An actor also has a `<name>`, and a thumb has its own `<title>` in some writers.
    /// Only the root's own children may describe the film.
    @Test func ignoresFieldsNestedInsideOtherElements() throws {
        let text = """
        <movie>
          <title>Real Title</title>
          <fileinfo><streamdetails><video><title>Nested Junk</title></video></streamdetails></fileinfo>
          <actor><name>Someone</name></actor>
          <genre>SF</genre>
        </movie>
        """
        let nfo = try #require(MediaNFOParser.parse(Data(text.utf8)))
        #expect(nfo.title == "Real Title")
        #expect(nfo.genres == ["SF"])
    }

    @Test func readsAPlotWrappedInCDATA() throws {
        let text = """
        <movie><title>X</title><plot><![CDATA[Ampersands & <angles> survive.]]></plot></movie>
        """
        let nfo = try #require(MediaNFOParser.parse(Data(text.utf8)))
        #expect(nfo.plot == "Ampersands & <angles> survive.")
    }

    @Test func returnsNothingForAFileThatIsNotAnNFO() {
        #expect(MediaNFOParser.parse(Data("<html><body>hi</body></html>".utf8)) == nil)
        #expect(MediaNFOParser.parse(Data("not xml at all".utf8)) == nil)
    }

    /// Kodi repeats the rating inside a `<ratings>` block; the first value is the one
    /// the writer meant.
    @Test func keepsTheFirstValueWhenAFieldRepeats() throws {
        let text = "<movie><title>A</title><rating>7.4</rating><rating>2.0</rating></movie>"
        let nfo = try #require(MediaNFOParser.parse(Data(text.utf8)))
        #expect(nfo.rating == 7.4)
    }
}
