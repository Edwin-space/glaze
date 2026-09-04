import Foundation
import Testing
@testable import GlazeCore

@Suite struct MetadataMatchRankerTests {
    private func match(
        _ title: String,
        year: Int?,
        original: String? = nil,
        popularity: Double = 10,
        votes: Int = 100,
        id: String = UUID().uuidString
    ) -> MediaMetadataMatch {
        MediaMetadataMatch(
            providerID: "tmdb",
            title: title,
            originalTitle: original,
            year: year,
            popularity: popularity,
            voteCount: votes,
            externalIDs: MediaExternalIDs(tmdbID: id)
        )
    }

    /// The case the viewer is asked about: one name, many films.
    @Test func putsTheRightYearFirstWhenOneNameCoversManyFilms() {
        let parsed = MediaTitleParser.parse("Dune.2021.2160p.BluRay.x265")
        let ranked = MetadataMatchRanker.rank(
            [
                match("Dune", year: 1984),
                match("Dune", year: 2021),
                match("Dune: Part Two", year: 2024)
            ],
            against: parsed
        )
        #expect(ranked.first?.match.year == 2021)
        #expect(ranked.first?.reasons.contains(.yearExact) == true)
        #expect(ranked.first?.reasons.contains(.titleExact) == true)
    }

    @Test func takesAnExactTitleAndYearWithoutAsking() {
        let parsed = MediaTitleParser.parse("Parasite.2019.1080p.BluRay")
        let ranked = MetadataMatchRanker.rank(
            [match("Parasite", year: 2019), match("Parasite", year: 1982)],
            against: parsed
        )
        #expect(MetadataMatchRanker.isUnambiguous(ranked))
    }

    /// Two equally good candidates must be put to the viewer rather than guessed at.
    @Test func asksWhenTwoCandidatesFitEquallyWell() {
        let parsed = MediaTitleParser.parse("The.Killer.2023.2160p.WEB-DL")
        let ranked = MetadataMatchRanker.rank(
            [match("The Killer", year: 2023), match("The Killer", year: 2023)],
            against: parsed
        )
        #expect(!MetadataMatchRanker.isUnambiguous(ranked))
    }

    /// A filename with no year cannot settle a remake; that has to be asked.
    @Test func asksWhenTheFilenameCarriesNoYear() {
        let parsed = MediaTitleParser.parse("Nosferatu.1080p.WEB-DL.x265")
        let ranked = MetadataMatchRanker.rank(
            [match("Nosferatu", year: 2024), match("Nosferatu", year: 1922)],
            against: parsed
        )
        #expect(!MetadataMatchRanker.isUnambiguous(ranked))
        #expect(ranked.first?.reasons.contains(.yearUnknown) == true)
    }

    /// A December release is dated the following year by half the world.
    @Test func forgivesAYearOffByOne() {
        let parsed = MediaTitleParser.parse("Avatar.Fire.and.Ash.2025.2160p.HDR10Plus.DV")
        let ranked = MetadataMatchRanker.rank(
            [match("Avatar: Fire and Ash", year: 2026), match("Avatar", year: 2009)],
            against: parsed
        )
        #expect(ranked.first?.match.year == 2026)
        #expect(ranked.first?.reasons.contains(.yearNear) == true)
    }

    /// Korean libraries routinely hold both names in one filename.
    @Test func matchesAKoreanFilenameThroughItsOriginalTitle() {
        let parsed = MediaTitleParser.parse("듄 파트2(내장)Dune Part Two (2024) 2160p BluRay x265")
        let ranked = MetadataMatchRanker.rank(
            [
                match("듄: 파트2", year: 2024, original: "Dune: Part Two"),
                match("Dune", year: 2021, original: "Dune")
            ],
            against: parsed
        )
        #expect(ranked.first?.match.year == 2024)
    }

    /// Fame breaks a tie; it never makes one.
    @Test func usesFameOnlyToSeparateOtherwiseEqualCandidates() {
        let parsed = MediaTitleParser.parse("Avatar.2009.1080p")
        let famous = match("Avatar", year: 2009, popularity: 180, votes: 30_000)
        let obscure = match("Avatar", year: 2009, popularity: 0.4, votes: 3)
        let ranked = MetadataMatchRanker.rank([obscure, famous], against: parsed)
        #expect(ranked.first?.match.popularity == 180)

        // A famous film with the wrong year still loses to an unknown one with the right year.
        let wrongYearFamous = match("Avatar", year: 2022, popularity: 300, votes: 40_000)
        let rightYearObscure = match("Avatar", year: 2009, popularity: 0.2, votes: 1)
        let second = MetadataMatchRanker.rank([wrongYearFamous, rightYearObscure], against: parsed)
        #expect(second.first?.match.year == 2009)
    }

    @Test func scoresTitlesTheWayAReaderWould() {
        #expect(MetadataMatchRanker.similarity("Dune", "Dune") == 1)
        #expect(MetadataMatchRanker.similarity("The Bear", "the bear!") == 1)
        #expect(MetadataMatchRanker.similarity("Dune Part Two", "Dune: Part Two") == 1)
        #expect(MetadataMatchRanker.similarity("Dune", "Dune Part Two") > 0.5)
        #expect(MetadataMatchRanker.similarity("Dune", "Parasite") < 0.3)
    }

    @Test func returnsNothingForNoCandidatesRatherThanFailing() {
        #expect(MetadataMatchRanker.rank([], against: MediaTitleParser.parse("X.2020.mkv")).isEmpty)
        #expect(!MetadataMatchRanker.isUnambiguous([]))
    }
}

/// Checked against what TMDB actually answers, which is where these rules came from.
@Suite struct RankerAgainstRealAnswersTests {
    private func match(
        _ title: String,
        year: Int?,
        original: String? = nil,
        matching: [String] = [],
        votes: Int = 100
    ) -> MediaMetadataMatch {
        MediaMetadataMatch(
            providerID: "tmdb",
            title: title,
            originalTitle: original,
            matchingTitles: matching,
            year: year,
            voteCount: votes,
            externalIDs: MediaExternalIDs(tmdbID: "\(title)-\(year ?? 0)")
        )
    }

    /// Asking TMDB in Korean returns 기생충, whose original title is also Korean. Without
    /// the international title to match on, the right film ranked below a wrong one.
    @Test func findsAKoreanFilmFromItsInternationalName() {
        let parsed = MediaTitleParser.parse("Parasite.2019.1080p.BluRay.x264")
        let ranked = MetadataMatchRanker.rank(
            [
                match("Parasites", year: 2019),
                match("기생충", year: 2019, original: "기생충", matching: ["Parasite"], votes: 18_000)
            ],
            against: parsed
        )
        #expect(ranked.first?.match.title == "기생충")
        #expect(ranked.first?.reasons.contains(.titleExact) == true)
        // Certain on its own terms, so it is written without asking.
        #expect(MetadataMatchRanker.isUnambiguous(ranked))
    }

    /// A near-namesake sitting close behind must not turn a certain match into a question.
    @Test func doesNotAskAboutACertainMatchJustBecauseANamesakeIsClose() {
        let parsed = MediaTitleParser.parse("Parasite.2019.1080p")
        let ranked = MetadataMatchRanker.rank(
            [
                match("기생충", year: 2019, matching: ["Parasite"], votes: 18_000),
                match("封印映像44 寄生虫", year: 2019, matching: ["Parasite 44"])
            ],
            against: parsed
        )
        #expect(MetadataMatchRanker.isUnambiguous(ranked))
    }

    /// Six films called Nosferatu and no year in the filename stays a question.
    @Test func stillAsksWhenTheYearIsMissingAndTheNameIsShared() {
        let parsed = MediaTitleParser.parse("Nosferatu.1080p.WEB-DL.x265-GROUP")
        let ranked = MetadataMatchRanker.rank(
            [
                match("노스페라투", year: 2024, original: "Nosferatu", votes: 4_000),
                match("노스페라투", year: 1922, original: "Nosferatu", votes: 2_000),
                match("Nosferatu", year: 1991)
            ],
            against: parsed
        )
        #expect(!MetadataMatchRanker.isUnambiguous(ranked))
        #expect(ranked.first?.reasons.contains(.yearUnknown) == true)
    }
}
