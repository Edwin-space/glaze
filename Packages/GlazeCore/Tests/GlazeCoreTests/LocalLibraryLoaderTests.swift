import Foundation
import Testing
@testable import GlazeCore

@Suite("A folder on the device reads as a library")
struct LocalLibraryLoaderTests {
    /// Builds a throwaway folder tree and hands back its root.
    private func makeTree(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-local-\(UUID().uuidString)", isDirectory: true)
        for path in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: url)
        }
        return root
    }

    @Test("Finds a film and the subtitle sitting beside it")
    func findsAFilmAndItsSubtitle() async throws {
        let root = try makeTree([
            "Parasite (2019)/Parasite.2019.1080p.mkv",
            "Parasite (2019)/Parasite.2019.1080p.ko.srt",
            "Parasite (2019)/Parasite.2019.1080p-poster.jpg"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let library = await LocalLibraryLoader().load(root: root)
        let film = try #require(library.movies.first)

        #expect(library.movies.count == 1)
        #expect(film.subtitleURLs.count == 1)
        #expect(film.subtitleURLs.first?.lastPathComponent == "Parasite.2019.1080p.ko.srt")
        #expect(film.posterURL?.lastPathComponent == "Parasite.2019.1080p-poster.jpg")
    }

    @Test("Groups episodes into a show, as the NAS loader does")
    func groupsEpisodes() async throws {
        let root = try makeTree([
            "The Bear/Season 01/The.Bear.S01E01.mkv",
            "The Bear/Season 01/The.Bear.S01E02.mkv",
            "The Bear/Season 02/The.Bear.S02E01.mkv"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let library = await LocalLibraryLoader().load(root: root)
        let show = try #require(library.series.first)

        #expect(library.series.count == 1)
        #expect(show.episodeCount == 3)
        #expect(show.seasons.count == 2)
    }

    @Test("Ignores what a Mac leaves behind when copying")
    func ignoresAppleDoubles() async throws {
        let root = try makeTree([
            "Film.mkv",
            "._Film.mkv",
            ".DS_Store",
            "notes.txt"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let library = await LocalLibraryLoader().load(root: root)
        #expect(library.movies.count == 1)
        #expect(library.movies.first?.sourceName == "Film.mkv")
    }

    @Test("Stops rather than walking a whole disk")
    func respectsTheFolderCeiling() async throws {
        var paths: [String] = []
        for index in 0..<12 {
            paths.append("folder\(index)/Film\(index).mkv")
        }
        let root = try makeTree(paths)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = await LocalLibraryLoader(limits: .init(depth: 5, folders: 4))
            .load(root: root)
        #expect(library.movies.count < 12)
    }
}
