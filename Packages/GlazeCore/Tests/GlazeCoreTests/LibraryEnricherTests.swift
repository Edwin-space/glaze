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
    /// `search/movie` answers `The.Bear.S01E01` with films. Offering those would invite
    /// writing a film's details onto an episode.
    @Test func doesNotOfferFilmsAsAnswersForAnEpisode() async {
        let provider = StubEpisodeProvider()
        let destination = EpisodeRecordingDestination()
        let enricher = LibraryEnricher(provider: provider) { _ in nil }

        let episode = MediaLibraryItem(
            id: "e1",
            sourceName: "The.Bear.S01E01.1080p.WEB-DL.mkv",
            parsed: MediaTitleParser.parse("The.Bear.S01E01.1080p.WEB-DL.mkv"),
            playbackURL: URL(string: "https://nas.local/e1.mkv")!
        )

        let outcomes = await enricher.enrich(
            [episode], languageCode: "ko", destination: { _ in destination }
        )
        #expect(outcomes["e1"] == .unsupportedKind)
        #expect(await destination.written.isEmpty)
    }
}

private struct StubEpisodeProvider: MetadataProviding {
    let providerID = "stub"
    func search(title: String, year: Int?, languageCode: String) async throws -> [MediaMetadataMatch] {
        [MediaMetadataMatch(providerID: "stub", title: "The Bear", year: 2022)]
    }
}

private actor EpisodeRecordingDestination: SidecarDestination {
    private(set) var written: [String] = []
    func write(_ data: Data, named name: String) async throws { written.append(name) }
}
