import Foundation
import Testing
@testable import GlazeCore

private struct StubProvider: MetadataProviding {
    let providerID = "stub"
    let results: [String: [MediaMetadataMatch]]
    var failure: MetadataProviderError?

    func search(title: String, year: Int?, languageCode: String) async throws -> [MediaMetadataMatch] {
        if let failure { throw failure }
        return results[title] ?? []
    }
}

private actor RecordingDestination: SidecarDestination {
    private(set) var written: [(name: String, data: Data)] = []

    func write(_ data: Data, named name: String) async throws {
        written.append((name, data))
    }
}

@Suite struct LibraryEnricherTests {
    private func item(_ name: String, nfo: MediaNFO? = nil) -> MediaLibraryItem {
        MediaLibraryItem(
            id: name,
            sourceName: name,
            parsed: MediaTitleParser.parse(name),
            metadata: nfo,
            playbackURL: URL(string: "https://nas.local/\(name)")!
        )
    }

    private func match(_ title: String, year: Int?, poster: String? = nil) -> MediaMetadataMatch {
        MediaMetadataMatch(
            providerID: "stub",
            title: title,
            year: year,
            posterURL: poster.map { URL(string: $0)! },
            externalIDs: MediaExternalIDs(tmdbID: "\(title)-\(year ?? 0)")
        )
    }

    @Test func describesAFilmItIsSureAbout() async {
        let provider = StubProvider(results: ["Parasite": [match("Parasite", year: 2019, poster: "https://img/p.jpg")]])
        let destination = RecordingDestination()
        let enricher = LibraryEnricher(provider: provider) { _ in Data("jpeg".utf8) }

        let outcomes = await enricher.enrich(
            [item("Parasite.2019.1080p.BluRay.mkv")],
            languageCode: "ko",
            destination: { _ in destination }
        )

        #expect(outcomes["Parasite.2019.1080p.BluRay.mkv"] == .written(["Parasite.2019.1080p.BluRay.nfo", "Parasite.2019.1080p.BluRay-poster.jpg"]))
        #expect(await destination.written.map(\.name).contains("Parasite.2019.1080p.BluRay.nfo"))
    }

    /// The whole point of asking: two films with one name and nothing to separate them.
    @Test func asksRatherThanGuessingWhenTheFilenameCannotSettleIt() async {
        let provider = StubProvider(results: [
            "Nosferatu": [match("Nosferatu", year: 2024), match("Nosferatu", year: 1922)]
        ])
        let destination = RecordingDestination()
        let enricher = LibraryEnricher(provider: provider) { _ in nil }

        let outcomes = await enricher.enrich(
            [item("Nosferatu.1080p.WEB-DL.mkv")],
            languageCode: "ko",
            destination: { _ in destination }
        )

        guard case .needsChoice(let ranked)? = outcomes["Nosferatu.1080p.WEB-DL.mkv"] else {
            Issue.record("expected a question, got \(String(describing: outcomes.values.first))")
            return
        }
        #expect(ranked.count == 2)
        // Nothing is written until the viewer answers.
        #expect(await destination.written.isEmpty)
    }

    @Test func writesTheFilmTheViewerPicked() async {
        let provider = StubProvider(results: [:])
        let destination = RecordingDestination()
        let enricher = LibraryEnricher(provider: provider) { _ in nil }
        let chosen = match("노스페라투", year: 1922)

        let outcome = await enricher.apply(
            chosen,
            to: item("Nosferatu.1080p.WEB-DL.mkv"),
            destination: { _ in destination }
        )

        #expect(outcome == .written(["Nosferatu.1080p.WEB-DL.nfo"]))
        let nfo = await String(data: destination.written[0].data, encoding: .utf8) ?? ""
        #expect(nfo.contains("<title>노스페라투</title>"))
    }

    /// A library someone curated in Kodi must survive a scan.
    @Test func leavesAFilmThatAlreadyHasAnNFOAlone() async {
        let provider = StubProvider(results: ["Parasite": [match("Parasite", year: 2019)]])
        let destination = RecordingDestination()
        let enricher = LibraryEnricher(provider: provider) { _ in nil }

        let described = item("Parasite.2019.mkv", nfo: MediaNFO(kind: .movie, title: "기생충", year: 2019))
        let outcomes = await enricher.enrich(
            [described], languageCode: "ko", destination: { _ in destination }
        )

        #expect(outcomes["Parasite.2019.mkv"] == .alreadyDescribed)
        #expect(await destination.written.isEmpty)
    }

    @Test func describesItAnywayWhenAskedToOverwrite() async {
        let provider = StubProvider(results: ["Parasite": [match("Parasite", year: 2019)]])
        let destination = RecordingDestination()
        let enricher = LibraryEnricher(provider: provider) { _ in nil }

        let described = item("Parasite.2019.mkv", nfo: MediaNFO(kind: .movie, title: "옛 제목", year: 2019))
        let outcomes = await enricher.enrich(
            [described],
            languageCode: "ko",
            destination: { _ in destination },
            overwriteExisting: true
        )

        #expect(outcomes["Parasite.2019.mkv"] == .written(["Parasite.2019.nfo"]))
    }

    @Test func reportsAFilmTheProviderHasNeverHeardOf() async {
        let provider = StubProvider(results: [:])
        let enricher = LibraryEnricher(provider: provider) { _ in nil }
        let outcomes = await enricher.enrich(
            [item("Some.Home.Video.2024.mkv")],
            languageCode: "ko",
            destination: { _ in RecordingDestination() }
        )
        #expect(outcomes["Some.Home.Video.2024.mkv"] == .notFound)
    }

    /// One film the service refuses must not stop the rest of the library.
    @Test func keepsGoingWhenTheServiceRefuses() async {
        let provider = StubProvider(results: [:], failure: .rateLimited)
        let enricher = LibraryEnricher(provider: provider) { _ in nil }
        let outcomes = await enricher.enrich(
            [item("A.2020.mkv"), item("B.2021.mkv")],
            languageCode: "ko",
            destination: { _ in RecordingDestination() }
        )
        #expect(outcomes.count == 2)
        for outcome in outcomes.values {
            guard case .failed = outcome else {
                Issue.record("expected a failure, got \(outcome)")
                return
            }
        }
    }

    @Test func reportsProgressAsItGoes() async {
        let provider = StubProvider(results: [:])
        let enricher = LibraryEnricher(provider: provider) { _ in nil }
        let seen = ProgressLog()

        _ = await enricher.enrich(
            [item("A.2020.mkv"), item("B.2021.mkv")],
            languageCode: "ko",
            destination: { _ in RecordingDestination() },
            onProgress: { seen.append($0) }
        )

        #expect(seen.values.map(\.completed) == [0, 1, 2])
        #expect(seen.values.allSatisfy { $0.total == 2 })
    }

    @Test func namesSidecarsAfterTheFilmsOwnStem() {
        #expect(LibraryEnricher.baseName(of: "Parasite.2019.1080p.mkv") == "Parasite.2019.1080p")
        #expect(LibraryEnricher.baseName(of: "no-extension") == "no-extension")
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LibraryEnricher.Progress] = []

    func append(_ progress: LibraryEnricher.Progress) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(progress)
    }

    var values: [LibraryEnricher.Progress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite struct LibraryEnricherEpisodeTests {
    private func episode(_ name: String, id: String) -> MediaLibraryItem {
        MediaLibraryItem(
            id: id,
            sourceName: name,
            parsed: MediaTitleParser.parse(name),
            playbackURL: URL(string: "https://nas.local/\(id).mkv")!
        )
    }

    /// A series is looked up in the series index, not the film one.
    @Test func describesAnEpisodeFromTheSeriesIndex() async {
        let provider = StubEpisodeProvider()
        let destination = EpisodeRecordingDestination()
        let enricher = LibraryEnricher(provider: provider) { _ in Data("jpeg".utf8) }

        let outcomes = await enricher.enrich(
            [episode("The.Bear.S01E01.The.Beef.1080p.WEB-DL.mkv", id: "e1")],
            languageCode: "ko",
            destination: { _ in destination }
        )

        #expect(outcomes["e1"] == .written(["The.Bear.S01E01.The.Beef.1080p.WEB-DL.nfo", "The.Bear.S01E01.The.Beef.1080p.WEB-DL-poster.jpg"]))
        let nfo = await destination.contents(named: "The.Bear.S01E01.The.Beef.1080p.WEB-DL.nfo") ?? ""
        #expect(nfo.contains("<episodedetails>"))
        #expect(nfo.contains("<showtitle>더 베어</showtitle>"))
        #expect(nfo.contains("<season>1</season>"))
        #expect(nfo.contains("<episode>1</episode>"))
        #expect(nfo.contains("<title>The Beef</title>"))
    }

    /// The poster is written once for a show, not once per episode.
    @Test func writesOnePosterForAWholeShow() async {
        let provider = StubEpisodeProvider()
        let destination = EpisodeRecordingDestination()
        let enricher = LibraryEnricher(provider: provider) { _ in Data("jpeg".utf8) }

        _ = await enricher.enrich(
            [
                episode("The.Bear.S01E01.1080p.mkv", id: "e1"),
                episode("The.Bear.S01E02.1080p.mkv", id: "e2"),
                episode("The.Bear.S01E03.1080p.mkv", id: "e3")
            ],
            languageCode: "ko",
            destination: { _ in destination }
        )

        let written = await destination.written
        #expect(written.filter { $0.hasSuffix(".nfo") }.count == 3)
        #expect(written.filter { $0.hasSuffix("-poster.jpg") }.count == 1)
    }

    /// One search for a show, however many episodes it has.
    @Test func looksAShowUpOnceRatherThanOncePerEpisode() async {
        let provider = StubEpisodeProvider()
        let enricher = LibraryEnricher(provider: provider) { _ in nil }

        _ = await enricher.enrich(
            (1...5).map { episode("The.Bear.S01E0\($0).mkv", id: "e\($0)") },
            languageCode: "ko",
            destination: { _ in EpisodeRecordingDestination() }
        )
        #expect(await provider.seriesSearchCount == 1)
    }

    /// Answering once applies to every episode of the show.
    @Test func appliesOneAnswerToEveryEpisode() async {
        let destination = EpisodeRecordingDestination()
        let enricher = LibraryEnricher(provider: StubEpisodeProvider()) { _ in Data("jpeg".utf8) }
        let chosen = MediaMetadataMatch(providerID: "stub", title: "더 베어", year: 2022)

        let outcomes = await enricher.applySeries(
            chosen,
            to: [episode("The.Bear.S01E01.mkv", id: "e1"), episode("The.Bear.S01E02.mkv", id: "e2")],
            destination: { _ in destination }
        )

        #expect(outcomes.count == 2)
        for outcome in outcomes.values {
            guard case .written = outcome else {
                Issue.record("expected both episodes written, got \(outcome)")
                return
            }
        }
    }
}

private actor StubEpisodeProvider: MetadataProviding {
    nonisolated let providerID = "stub"
    private(set) var seriesSearchCount = 0

    /// The film index has never heard of it, which is the point.
    nonisolated func search(title: String, year: Int?, languageCode: String) async throws -> [MediaMetadataMatch] {
        []
    }

    func searchSeries(title: String, year: Int?, languageCode: String) async throws -> [MediaMetadataMatch] {
        seriesSearchCount += 1
        return [
            MediaMetadataMatch(
                providerID: "stub",
                title: "더 베어",
                originalTitle: "The Bear",
                year: 2022,
                overview: "시카고의 샌드위치 가게.",
                posterURL: URL(string: "https://img/bear.jpg"),
                voteCount: 5_000,
                externalIDs: MediaExternalIDs(tmdbID: "136315")
            )
        ]
    }
}

private actor EpisodeRecordingDestination: SidecarDestination {
    private(set) var written: [String] = []
    private var bodies: [String: Data] = [:]

    func write(_ data: Data, named name: String) async throws {
        written.append(name)
        bodies[name] = data
    }

    func contents(named name: String) -> String? {
        bodies[name].flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// A library described by someone else — or by an earlier run that had no artwork —
/// stays a wall of grey rectangles unless the poster can be filled in on its own.
@Suite struct LibraryEnricherPosterOnlyTests {
    private func described(_ name: String, id: String, poster: URL? = nil) -> MediaLibraryItem {
        MediaLibraryItem(
            id: id,
            sourceName: name,
            parsed: MediaTitleParser.parse(name),
            metadata: MediaNFO(kind: .movie, title: "기생충", year: 2019),
            posterURL: poster,
            playbackURL: URL(string: "https://nas.local/\(id).mkv")!
        )
    }

    @Test func addsTheMissingPosterWithoutRewritingTheDescription() async {
        let destination = PosterDestination()
        let enricher = LibraryEnricher(provider: PosterStubProvider()) { _ in Data("jpeg".utf8) }

        let outcomes = await enricher.enrich(
            [described("Parasite.2019.1080p.mkv", id: "m1")],
            languageCode: "ko",
            destination: { _ in destination }
        )

        #expect(outcomes["m1"] == .posterAdded("Parasite.2019.1080p-poster.jpg"))
        let written = await destination.written
        #expect(written == ["Parasite.2019.1080p-poster.jpg"])
        #expect(!written.contains { $0.hasSuffix(".nfo") })
    }

    /// Seen on a real NAS: five copies of one show's poster, one per run. An episode
    /// that already carries the artwork has to count as the show's poster, or the next
    /// run hands a second copy to the next episode along.
    @Test func doesNotAddASecondPosterToAShowThatAlreadyHasOne() async {
        let destination = PosterDestination()
        let enricher = LibraryEnricher(provider: PosterStubProvider()) { _ in Data("jpeg".utf8) }

        func episode(_ index: Int, poster: URL?) -> MediaLibraryItem {
            MediaLibraryItem(
                id: "e\(index)",
                sourceName: String(format: "Fallout.S01E%02d.2160p.mkv", index),
                parsed: MediaTitleParser.parse(String(format: "Fallout.S01E%02d.2160p.mkv", index)),
                metadata: MediaNFO(kind: .episode, title: "T", showTitle: "폴아웃", season: 1, episode: index),
                posterURL: poster,
                playbackURL: URL(string: "https://nas.local/e\(index).mkv")!
            )
        }

        // The state a second run finds: episode one already has the poster.
        let episodes = [episode(1, poster: URL(string: "https://nas/p.jpg")!)]
            + (2...5).map { episode($0, poster: nil) }

        _ = await enricher.enrich(episodes, languageCode: "ko", destination: { _ in destination })
        #expect(await destination.written.isEmpty)
    }

    @Test func leavesAFilmThatAlreadyHasArtworkAlone() async {
        let destination = PosterDestination()
        let enricher = LibraryEnricher(provider: PosterStubProvider()) { _ in Data("jpeg".utf8) }

        let outcomes = await enricher.enrich(
            [described("Parasite.2019.mkv", id: "m1", poster: URL(string: "https://nas/p.jpg")!)],
            languageCode: "ko",
            destination: { _ in destination }
        )

        #expect(outcomes["m1"] == .alreadyDescribed)
        #expect(await destination.written.isEmpty)
    }
}

private struct PosterStubProvider: MetadataProviding {
    let providerID = "stub"
    func search(title: String, year: Int?, languageCode: String) async throws -> [MediaMetadataMatch] {
        [MediaMetadataMatch(
            providerID: "stub",
            title: "기생충",
            matchingTitles: ["Parasite"],
            year: 2019,
            posterURL: URL(string: "https://img/p.jpg"),
            voteCount: 9_000,
            externalIDs: MediaExternalIDs(tmdbID: "496243")
        )]
    }
}

private actor PosterDestination: SidecarDestination {
    private(set) var written: [String] = []
    func write(_ data: Data, named name: String) async throws { written.append(name) }
}
