import Foundation
import Testing
@testable import GlazeCore

struct WebDAVPropfindParserTests {
    private let base = URL(string: "https://nas.local:5006/video/")!

    /// Synology's shape: `D:` prefix, absolute-path hrefs, the listed folder returned
    /// as the first response.
    private let synology = """
    <?xml version="1.0" encoding="utf-8"?>
    <D:multistatus xmlns:D="DAV:">
      <D:response>
        <D:href>/video/</D:href>
        <D:propstat><D:prop>
          <D:displayname>video</D:displayname>
          <D:resourcetype><D:collection/></D:resourcetype>
        </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
      </D:response>
      <D:response>
        <D:href>/video/Media/</D:href>
        <D:propstat><D:prop>
          <D:displayname>Media</D:displayname>
          <D:resourcetype><D:collection/></D:resourcetype>
        </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
      </D:response>
      <D:response>
        <D:href>/video/Avengers.Endgame.2019.mkv</D:href>
        <D:propstat><D:prop>
          <D:displayname>Avengers.Endgame.2019.mkv</D:displayname>
          <D:resourcetype/>
          <D:getcontentlength>2846355041</D:getcontentlength>
          <D:getcontenttype>application/octet-stream</D:getcontenttype>
          <D:getlastmodified>Wed, 29 May 2026 17:07:26 GMT</D:getlastmodified>
        </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
      </D:response>
    </D:multistatus>
    """

    @Test func readsFoldersAndFiles() {
        let entries = WebDAVPropfindParser.parse(Data(synology.utf8), baseURL: base)

        #expect(entries.map(\.name) == ["Media", "Avengers.Endgame.2019.mkv"])
        #expect(entries[0].isDirectory)
        #expect(!entries[1].isDirectory)
    }

    /// Listing a folder returns the folder itself first. Keeping it would give every
    /// folder a child of its own name that leads back to where you already are.
    @Test func leavesOutTheFolderBeingListed() {
        let entries = WebDAVPropfindParser.parse(Data(synology.utf8), baseURL: base)

        #expect(!entries.contains { $0.name == "video" })
    }

    @Test func leavesOutTheFolderWhenTheServerChangesURLSpelling() {
        let response = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>HTTPS://NAS.LOCAL:5006/video</D:href>
            <D:propstat><D:prop>
              <D:displayname>video</D:displayname>
              <D:resourcetype><D:collection/></D:resourcetype>
            </D:prop></D:propstat>
          </D:response>
        </D:multistatus>
        """

        #expect(WebDAVPropfindParser.parse(Data(response.utf8), baseURL: base).isEmpty)
    }

    @Test func readsSizeAndDate() {
        let entries = WebDAVPropfindParser.parse(Data(synology.utf8), baseURL: base)
        let film = entries[1]

        #expect(film.byteCount == 2_846_355_041)
        #expect(film.lastModified != nil)
    }

    @Test func resolvesAbsolutePathHrefsAgainstTheServer() {
        let entries = WebDAVPropfindParser.parse(Data(synology.utf8), baseURL: base)

        #expect(entries[1].url.absoluteString == "https://nas.local:5006/video/Avengers.Endgame.2019.mkv")
    }

    /// The DAV: namespace may carry any prefix, and servers disagree. Keying on the
    /// prefix works against one and silently returns nothing against the next.
    @Test func acceptsAnyNamespacePrefix() {
        let apache = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:ns0="DAV:">
          <d:response>
            <d:href>https://nas.local:5006/video/Dune.2024.mkv</d:href>
            <d:propstat><d:prop>
              <ns0:displayname>Dune.2024.mkv</ns0:displayname>
              <d:resourcetype/>
              <d:getcontentlength>123</d:getcontentlength>
            </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
        </d:multistatus>
        """

        let entries = WebDAVPropfindParser.parse(Data(apache.utf8), baseURL: base)

        #expect(entries.map(\.name) == ["Dune.2024.mkv"])
        #expect(entries[0].byteCount == 123)
    }

    /// A server that sends no displayname is within its rights; the name has to come
    /// out of the path, percent-decoded.
    @Test func fallsBackToThePathWhenThereIsNoDisplayName() {
        let terse = """
        <?xml version="1.0"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/video/%EA%B1%B4%EC%B6%95%ED%95%99%20%EA%B0%9C%EB%A1%A0.mkv</D:href>
            <D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat>
          </D:response>
        </D:multistatus>
        """

        let entries = WebDAVPropfindParser.parse(Data(terse.utf8), baseURL: base)

        #expect(entries.map(\.name) == ["건축학 개론.mkv"])
    }

    @Test func recognisesVideosByExtension() {
        let entries = WebDAVPropfindParser.parse(Data(synology.utf8), baseURL: base)

        // Reported as application/octet-stream by the server, which is what a NAS says
        // about Matroska.
        #expect(entries[1].isVideo)
        #expect(!entries[0].isVideo)
    }

    @Test func returnsNothingForAnUnreadableResponse() {
        #expect(WebDAVPropfindParser.parse(Data("not xml".utf8), baseURL: base).isEmpty)
    }
}

/// The point of WebDAV: finding what sits beside a film. Over DLNA this is impossible —
/// a film is `80.mkv` and nothing can be asked about its neighbours.
struct WebDAVCompanionFinderTests {
    private func entry(_ name: String, directory: Bool = false) -> WebDAVEntry {
        WebDAVEntry(
            url: URL(string: "https://nas.local/video/\(name)")!,
            name: name,
            isDirectory: directory
        )
    }

    private var folder: [WebDAVEntry] {
        [
            entry("Avatar.2025.mkv"),
            entry("Avatar.2025.ko.srt"),
            entry("Avatar.2025.en.srt"),
            entry("Avatar.2025-poster.jpg"),
            entry("Avatar.2025.nfo"),
            entry("Avatar.2025.Behind.The.Scenes.mkv"),
            entry("Dune.2024.mkv"),
            entry("Dune.2024.ko.srt"),
            entry("Extras", directory: true)
        ]
    }

    @Test func findsSubtitlesBesideTheFilm() {
        let found = WebDAVCompanionFinder.find(for: entry("Avatar.2025.mkv"), among: folder)

        #expect(found.subtitles.map(\.name) == ["Avatar.2025.en.srt", "Avatar.2025.ko.srt"])
    }

    @Test func findsThePosterAndTheNfo() {
        let found = WebDAVCompanionFinder.find(for: entry("Avatar.2025.mkv"), among: folder)

        #expect(found.poster?.name == "Avatar.2025-poster.jpg")
        #expect(found.nfo?.name == "Avatar.2025.nfo")
    }

    /// A folder holds more than one film, and their names often share a prefix.
    @Test func doesNotTakeTheNeighboursSubtitles() {
        let found = WebDAVCompanionFinder.find(for: entry("Dune.2024.mkv"), among: folder)

        #expect(found.subtitles.map(\.name) == ["Dune.2024.ko.srt"])
        #expect(found.poster == nil)
    }

    /// Another video sharing the prefix is a separate film, not a companion.
    @Test func doesNotTreatAnotherFilmAsACompanion() {
        let found = WebDAVCompanionFinder.find(for: entry("Avatar.2025.mkv"), among: folder)

        #expect(!found.subtitles.contains { $0.name.hasSuffix(".mkv") })
    }

    @Test func hasNothingToFindForAFilmOnItsOwn() {
        let alone = [entry("Solo.2019.mkv")]

        #expect(WebDAVCompanionFinder.find(for: alone[0], among: alone).isEmpty)
    }

    /// Kodi's `-poster` name wins over a screenshot that happens to share the stem.
    @Test func prefersTheProperPosterName() {
        let mixed = [
            entry("Film.2020.mkv"),
            entry("Film.2020.screenshot.jpg"),
            entry("Film.2020-poster.jpg")
        ]

        #expect(WebDAVCompanionFinder.find(for: mixed[0], among: mixed).poster?.name == "Film.2020-poster.jpg")
    }
}

/// A Mac writing to a share leaves `._Film.mkv` beside every file it touches. Those
/// carry the video extension, and were being listed as films.
@Suite struct WebDAVHiddenEntryTests {
    private func entry(_ name: String, isDirectory: Bool = false) -> WebDAVEntry {
        WebDAVEntry(
            url: URL(string: "https://nas.local/\(name)")!,
            name: name,
            isDirectory: isDirectory
        )
    }

    @Test func doesNotTreatAppleDoubleFilesAsFilms() {
        #expect(!entry("._Fallout.S01E01.2160p.mkv").isVideo)
        #expect(entry("Fallout.S01E01.2160p.mkv").isVideo)
    }

    @Test func skipsTheOtherThingsFilesystemsLeaveBehind() {
        #expect(entry(".DS_Store").isHidden)
        #expect(entry("Thumbs.db").isHidden)
        #expect(entry("desktop.ini").isHidden)
        #expect(!entry("Film.2019.mkv").isHidden)
    }

    /// A poster hanging off `._Film.mkv` belongs to nothing anyone can watch.
    @Test func doesNotCountHiddenFilesAsCompanions() {
        let video = entry("Film.2019.mkv")
        let companions = WebDAVCompanionFinder.find(
            for: video,
            among: [video, entry("._Film.2019-poster.jpg"), entry("Film.2019-poster.jpg")]
        )
        #expect(companions.poster?.name == "Film.2019-poster.jpg")
    }
}

/// A NAS keeps folders for itself, and walking into them turns a library scan into a
/// scan of the whole disk.
@Suite struct WebDAVSystemFolderTests {
    private func folder(_ name: String) -> WebDAVEntry {
        WebDAVEntry(url: URL(string: "https://nas.local/\(name)/")!, name: name, isDirectory: true)
    }

    @Test func skipsWhatTheNASKeepsForItself() {
        // Synology writes a thumbnail for every indexed file into @eaDir, beside almost
        // everything.
        #expect(folder("@eaDir").isHidden)
        #expect(folder("#recycle").isHidden)
        #expect(folder("#snapshot").isHidden)
        #expect(folder("lost+found").isHidden)
        #expect(folder("$RECYCLE.BIN").isHidden)
        #expect(folder("System Volume Information").isHidden)
    }

    @Test func leavesRealFoldersAlone() {
        #expect(!folder("Media").isHidden)
        #expect(!folder("영화").isHidden)
        #expect(!folder("Fallout.S01.2160p").isHidden)
    }
}

/// A WebDAV root is every share on the NAS; a library lives in one of them.
@Suite struct WebDAVConnectionLibraryPathTests {
    private let root = URL(string: "https://nas.local:5006/")!

    @Test func scansTheChosenFolderRatherThanTheWholeShare() {
        let connection = WebDAVConnection(
            name: "집", rootURL: root, username: "someone", libraryPath: "Media"
        )
        #expect(connection.libraryURL.absoluteString == "https://nas.local:5006/Media/")
    }

    @Test func fallsBackToTheShareWhenNoFolderWasChosen() {
        let connection = WebDAVConnection(name: "집", rootURL: root, username: "someone")
        #expect(connection.libraryURL == root)
        #expect(WebDAVConnection(name: "집", rootURL: root, username: "s", libraryPath: "").libraryURL == root)
    }

    /// Connections saved before the field existed still decode.
    @Test func readsAConnectionSavedWithoutALibraryFolder() throws {
        let json = #"{"id":"a","name":"집","rootURL":"https://nas.local:5006/","username":"someone"}"#
        let decoded = try JSONDecoder().decode(WebDAVConnection.self, from: Data(json.utf8))
        #expect(decoded.libraryPath == nil)
        #expect(decoded.libraryURL.absoluteString == "https://nas.local:5006/")
    }
}
