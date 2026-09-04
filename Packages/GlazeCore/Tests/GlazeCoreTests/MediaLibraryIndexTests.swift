import Foundation
import Testing
@testable import GlazeCore

@Suite struct MediaLibraryIndexTests {
    private func item(
        _ name: String,
        nfo: MediaNFO? = nil,
        poster: String? = nil,
        added: Date? = nil
    ) -> LibraryItem {
        LibraryItem(
            id: name,
            sourceName: name,
            parsed: MediaTitleParser.parse(name),
            metadata: nfo,
            posterURL: poster.map { URL(string: $0)! },
            playbackURL: URL(string: "http://nas.local/\(name)")!,
            dateAdded: added
        )
    }

    @Test func gathersEpisodesIntoOneShowInsteadOfLooseFiles() {
        let library = MediaLibraryIndex.build(from: [
            item("The.Bear.S01E01.1080p.WEB-DL.mkv"),
            item("The.Bear.S01E02.1080p.WEB-DL.mkv"),
            item("The.Bear.S02E01.1080p.WEB-DL.mkv"),
            item("Parasite.2019.1080p.BluRay.mkv")
        ])

        #expect(library.movies.count == 1)
        #expect(library.movies[0].displayTitle == "Parasite")
        #expect(library.series.count == 1)

        let show = library.series[0]
        #expect(show.title == "The Bear")
        #expect(show.episodeCount == 3)
        #expect(show.seasons.map(\.number) == [1, 2])
        #expect(show.seasons[0].episodes.count == 2)
    }

    /// Release names for one show are rarely spelled the same way twice.
    @Test func treatsDifferentSpellingsOfAShowAsTheSameShow() {
        let library = MediaLibraryIndex.build(from: [
            item("The.Bear.S01E01.mkv"),
            item("the bear - s01e02.mkv"),
            item("The Bear S01E03.mkv")
        ])
        #expect(library.series.count == 1)
        #expect(library.series[0].episodeCount == 3)
    }

    @Test func ordersEpisodesByNumberRatherThanByFilename() {
        let library = MediaLibraryIndex.build(from: [
            item("Show.S01E10.mkv"),
            item("Show.S01E02.mkv"),
            item("Show.S01E01.mkv")
        ])
        let episodes = library.series[0].seasons[0].episodes
        #expect(episodes.map(\.episodeNumber) == [1, 2, 10])
    }

    /// An NFO saying `<movie>` settles it even when the filename looks like an episode.
    @Test func believesTheNFOOverTheFilename() {
        let library = MediaLibraryIndex.build(from: [
            item("Se7en.1995.mkv", nfo: MediaNFO(kind: .movie, title: "세븐", year: 1995))
        ])
        #expect(library.movies.count == 1)
        #expect(library.series.isEmpty)
        #expect(library.movies[0].displayTitle == "세븐")
    }

    @Test func namesAShowFromItsNFORatherThanItsFilename() {
        let library = MediaLibraryIndex.build(from: [
            item(
                "TB.S01E01.mkv",
                nfo: MediaNFO(kind: .episode, title: "System", showTitle: "더 베어", season: 1, episode: 1)
            )
        ])
        #expect(library.series.count == 1)
        #expect(library.series[0].title == "더 베어")
    }

    @Test func groupsSpecialsIntoSeasonZeroRatherThanADummySeason() {
        let library = MediaLibraryIndex.build(from: [
            item("Show.S00E01.Special.mkv"),
            item("Show.S01E01.mkv")
        ])
        #expect(library.series[0].seasons.map(\.number) == [0, 1])
    }

    @Test func ordersRecentlyAddedNewestFirstAndLeavesOutUndatedFiles() {
        let now = Date()
        let library = MediaLibraryIndex.build(from: [
            item("Old.2001.mkv", added: now.addingTimeInterval(-86_400)),
            item("New.2026.mkv", added: now),
            item("Undated.2020.mkv")
        ])
        #expect(library.recentlyAdded.map(\.sourceName) == ["New.2026.mkv", "Old.2001.mkv"])
    }

    @Test func buildsGenreShelvesFromNFOsAndOrdersThemByHowFullTheyAre() {
        let library = MediaLibraryIndex.build(from: [
            item("A.2020.mkv", nfo: MediaNFO(kind: .movie, title: "A", genres: ["드라마", "스릴러"])),
            item("B.2021.mkv", nfo: MediaNFO(kind: .movie, title: "B", genres: ["드라마"])),
            item("Show.S01E01.mkv", nfo: MediaNFO(kind: .episode, showTitle: "S", genres: ["드라마"], season: 1, episode: 1))
        ])
        #expect(library.genres.map(\.name) == ["드라마", "스릴러"])
        #expect(library.genres[0].count == 3)
        #expect(library.genres[0].series.count == 1)
    }

    /// Nothing scraped means no genre shelves at all, rather than one bucket of
    /// everything labelled "기타".
    @Test func offersNoGenresWhenNothingHasBeenScraped() {
        let library = MediaLibraryIndex.build(from: [item("A.2020.mkv"), item("B.2021.mkv")])
        #expect(library.genres.isEmpty)
    }

    @Test func takesTheShowPosterFromWhicheverEpisodeHasOne() {
        let library = MediaLibraryIndex.build(from: [
            item("Show.S01E01.mkv"),
            item("Show.S01E02.mkv", poster: "http://nas.local/Show.S01E02-poster.jpg")
        ])
        #expect(library.series[0].posterURL?.lastPathComponent == "Show.S01E02-poster.jpg")
    }

    @Test func labelsAnEpisodeTheWayAViewerReadsIt() {
        let episode = item("Show.S02E07.mkv")
        #expect(episode.episodeLabel == "S02E07")
        #expect(item("Parasite.2019.mkv").episodeLabel == nil)
    }
}
