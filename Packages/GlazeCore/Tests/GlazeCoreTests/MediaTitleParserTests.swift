import Foundation
import Testing
@testable import GlazeCore

/// Every input here is a real name taken off the NAS this was built against, not one I
/// made up to suit the parser.
struct MediaTitleParserTests {
    @Test func readsAFilmAndItsYear() {
        let parsed = MediaTitleParser.parse("Avengers.Endgame.2019.PROPER.2160p.BluRay.REMUX.HEVC.DTS-HD.MA.TrueHD.7.1.Atmos-FGT")

        #expect(parsed.title == "Avengers Endgame")
        #expect(parsed.year == 2019)
    }

    @Test func dropsTheSiteThatPackagedIt() {
        let parsed = MediaTitleParser.parse("PSArips.com | Avatar.Fire.and.Ash.2025.2160p.HDR10Plus.DV.WEBRip.6CH.x265.HEVC-PSA")

        #expect(parsed.title == "Avatar Fire and Ash")
        #expect(parsed.year == 2025)
    }

    @Test func readsSeasonAndEpisode() {
        let parsed = MediaTitleParser.parse("Fallout.S01E01.The.End.2160p.AMZN.WEB-DL.DDP5.1.HDR.H.265-NTb")

        #expect(parsed.title == "Fallout")
        #expect(parsed.season == 1)
        #expect(parsed.episode == 1)
    }

    @Test func readsASeasonWithNoEpisode() {
        let parsed = MediaTitleParser.parse("Star.Wars.Maul.-.Shadow.Lord.S01.1080p.DSNP.WEB-DL.DDP.5.1.Atmos.H.264-BlackTV")

        #expect(parsed.title == "Star Wars Maul - Shadow Lord")
        #expect(parsed.season == 1)
        #expect(parsed.episode == nil)
    }

    @Test func dropsBracketedMetadata() {
        let parsed = MediaTitleParser.parse("F1 The Movie (2025) [2160p] [4K] [WEB] [5.1] [YTS.MX]")

        #expect(parsed.title == "F1 The Movie")
        #expect(parsed.year == 2025)
    }

    /// Korean releases put the Korean title first and the English one after it. Both
    /// belong to the title; only what follows the year does not.
    @Test func keepsAKoreanTitle() {
        let parsed = MediaTitleParser.parse("건축학.개론.Architecture.101.2012.BRRip.1080p.x265.10bit.AC3-highcal")

        #expect(parsed.title == "건축학 개론 Architecture 101")
        #expect(parsed.year == 2012)
    }

    @Test func handlesACommaBeforeTheYear() {
        let parsed = MediaTitleParser.parse("나우 유 씨 미 3 Now You See Me Now You Don't, 2025.KORSUB.1080p.WEB-DL.H264.AAC")

        #expect(parsed.title == "나우 유 씨 미 3 Now You See Me Now You Don't")
        #expect(parsed.year == 2025)
    }

    @Test func marksResolutionAndDynamicRange() {
        let parsed = MediaTitleParser.parse("Avatar.Fire.and.Ash.2025.2160p.HDR10Plus.DV.WEBRip.6CH.x265.HEVC-PSA")

        #expect(parsed.badges.contains("4K"))
        #expect(parsed.badges.contains("HDR10+"))
        #expect(parsed.badges.contains("Dolby Vision"))
    }

    /// A shelf has room for a few marks, not for both HDR and HDR10+ saying the same
    /// thing, nor for two resolutions.
    @Test func doesNotRepeatItself() {
        let parsed = MediaTitleParser.parse("Film.2024.2160p.1080p.HDR10Plus.HDR.WEB")

        #expect(parsed.badges.filter { $0 == "1080p" }.isEmpty)
        #expect(parsed.badges.filter { $0 == "HDR" }.isEmpty)
        #expect(parsed.badges.contains("4K"))
        #expect(parsed.badges.contains("HDR10+"))
    }

    /// A name that is already readable must come through untouched.
    @Test func leavesAPlainTitleAlone() {
        let parsed = MediaTitleParser.parse("휴가")

        #expect(parsed.title == "휴가")
        #expect(parsed.year == nil)
        #expect(parsed.badges.isEmpty)
    }
}

/// The two facts DLNA does send about a file, which have to stand in for the artwork
/// it does not.
struct DIDLResourceDetailTests {
    private let didl = """
    <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" \
    xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
    <item id="33$@80" parentID="33$3" restricted="1">
    <dc:title>Avengers.Endgame.2019.2160p.BluRay</dc:title>
    <upnp:class>object.item.videoItem</upnp:class>
    <dc:date>2026-05-29T17:07:26</dc:date>
    <res protocolInfo="http-get:*:video/x-matroska:*" resolution="1920x816" size="2846355041" \
    duration="1:56:25.000">http://nas:50002/v/NDLNA/80.mkv</res>
    </item></DIDL-Lite>
    """

    @Test func keepsResolutionAndDateAdded() {
        let nodes = DIDLLiteParser.parse(data: Data(didl.utf8), serverID: "nas")
        guard case .video(let resource)? = nodes.first?.kind else {
            Issue.record("no video node parsed")
            return
        }

        #expect(resource.resolution == "1920x816")
        #expect(resource.dateAdded != nil)
        #expect(resource.duration == 6985)
    }
}

/// An episode list showing the whole release string is unreadable across a room.
@Suite struct EpisodeTitleParsingTests {
    @Test func readsTheEpisodeNameOutOfARelease() {
        let parsed = MediaTitleParser.parse("Fallout.S01E01.The.End.2160p.AMZN.WEB-DL.DDP5.1.HDR.H.265-NTb")
        #expect(parsed.title == "Fallout")
        #expect(parsed.season == 1)
        #expect(parsed.episode == 1)
        #expect(parsed.episodeTitle == "The End")
    }

    @Test func handlesSpacedAndHyphenatedReleases() {
        #expect(
            MediaTitleParser.parse("The Bear - S02E07 - Forks - 1080p WEB-DL").episodeTitle == "Forks"
        )
        #expect(
            MediaTitleParser.parse("Show.S01E03.A.Long.Way.Down.1080p.BluRay.x264").episodeTitle
                == "A Long Way Down"
        )
    }

    /// Most releases name no episode; saying so is better than inventing one.
    @Test func returnsNothingWhenTheReleaseNamesNoEpisode() {
        #expect(MediaTitleParser.parse("Show.S01E03.1080p.WEB-DL.x265").episodeTitle == nil)
        #expect(MediaTitleParser.parse("Show.S01E03").episodeTitle == nil)
    }

    @Test func leavesFilmsAlone() {
        #expect(MediaTitleParser.parse("Parasite.2019.1080p.BluRay.mkv").episodeTitle == nil)
    }

    /// A year inside an episode name is where the metadata starts, not part of it.
    @Test func stopsAtTheFirstPieceOfReleaseMetadata() {
        #expect(
            MediaTitleParser.parse("Show.S01E05.The.Reunion.2024.2160p.NF.WEB-DL").episodeTitle
                == "The Reunion"
        )
    }
}

/// Plenty of releases carry no year. Without a cut at the release metadata the whole
/// filename became the "title", and no metadata service finds anything for that.
@Suite struct TitleWithoutYearTests {
    @Test func cutsAtTheReleaseMetadataWhenThereIsNoYear() {
        #expect(MediaTitleParser.parse("Nosferatu.1080p.WEB-DL.x265-GROUP").title == "Nosferatu")
        #expect(MediaTitleParser.parse("Nosferatu.1080p.WEB-DL.x265-GROUP").year == nil)
        #expect(MediaTitleParser.parse("The Substance 2160p BluRay REMUX").title == "The Substance")
        #expect(MediaTitleParser.parse("Wicked.UHD.HDR.DV.Atmos").title == "Wicked")
    }

    /// A year still wins when there is one — the metadata cut is the fallback.
    @Test func stillPrefersTheYearWhenTheReleaseHasOne() {
        let parsed = MediaTitleParser.parse("Dune.Part.Two.2024.2160p.BluRay.x265")
        #expect(parsed.title == "Dune Part Two")
        #expect(parsed.year == 2024)
    }

    /// A title that is only a name has nothing to cut at, and must survive whole.
    @Test func leavesAPlainNameAlone() {
        #expect(MediaTitleParser.parse("Parasite").title == "Parasite")
        #expect(MediaTitleParser.parse("기생충").title == "기생충")
    }
}

/// Numbering seen in a real Korean library, neither of which is `S01E01`.
@Suite struct EpisodeNumberingVariantsTests {
    @Test func readsAnEpisodeWrittenWithoutASeason() {
        let parsed = MediaTitleParser.parse("메이드 인 코리아.Made In Korea.E02.1080p.DSNP.WEB-DL.DD+-Sniper")
        #expect(parsed.episode == 2)
        #expect(parsed.season == nil)
        #expect(parsed.title == "메이드 인 코리아 Made In Korea")
    }

    @Test func readsAKoreanEpisodeNumber() {
        let parsed = MediaTitleParser.parse("라이어니스- 특수 작전팀 2 3회.mp4")
        #expect(parsed.episode == 3)
        // The trailing 2 is the season, and is taken out of the show's name — see
        // `KoreanLibraryNamingTests`.
        #expect(parsed.title == "라이어니스- 특수 작전팀")
        #expect(parsed.season == 2)
    }

    /// A release group with digits in its name is not an episode number.
    @Test func doesNotReadAReleaseGroupAsAnEpisode() {
        #expect(MediaTitleParser.parse("Film.2019.1080p.BluRay.x264-SPARKS").episode == nil)
        #expect(MediaTitleParser.parse("Dune.Part.Two.2024.2160p.BluRay.x265").episode == nil)
    }

    @Test func stillPrefersTheSeasonFormWhenBothCouldMatch() {
        let parsed = MediaTitleParser.parse("Show.S02E07.The.Name.1080p.WEB-DL")
        #expect(parsed.season == 2)
        #expect(parsed.episode == 7)
    }
}

/// Filenames taken verbatim from a real Korean library, each of which found nothing.
@Suite struct KoreanLibraryNamingTests {
    @Test func offersBothHalvesOfAMixedScriptName() {
        let parsed = MediaTitleParser.parse("더 러닝 맨 The Running Man, 2025.KORSUB.1080p.WEB-DL.H264.AAC")
        #expect(parsed.year == 2025)
        #expect(parsed.alternateTitles.contains("더 러닝 맨"))
        #expect(parsed.alternateTitles.contains("The Running Man"))
    }

    /// Here the English name sits after the year, where truncation cuts it away.
    @Test func keepsAnEnglishNameThatFollowsTheYear() {
        let parsed = MediaTitleParser.parse("슈퍼 마리오 갤럭시 (2026) The Super Mario Galaxy Movie.KORsub.1080p.FHD")
        #expect(parsed.title == "슈퍼 마리오 갤럭시")
        #expect(parsed.alternateTitles.contains("The Super Mario Galaxy Movie"))
    }

    /// `2026-2160p`: a hyphen after the year is still a boundary.
    @Test func readsAYearFollowedByAHyphen() {
        let parsed = MediaTitleParser.parse("Tom.Clancys.Jack.Ryan.Ghost.War.2026-2160p.HDR.DV.WEB.ATMOS.AV1")
        #expect(parsed.year == 2026)
        #expect(parsed.title == "Tom Clancys Jack Ryan Ghost War")
    }

    /// A show numbered in its own name carries its season there.
    @Test func readsASeasonWrittenIntoTheShowsName() {
        let parsed = MediaTitleParser.parse("라이어니스- 특수 작전팀 2 3회")
        #expect(parsed.title == "라이어니스- 특수 작전팀")
        #expect(parsed.season == 2)
        #expect(parsed.episode == 3)
    }

    /// A film with a number in its name keeps it: `Toy Story 5` is not a season.
    @Test func leavesANumberedFilmAlone() {
        let parsed = MediaTitleParser.parse("Toy Story 5 (2026) [1080p] [WEBRip]")
        #expect(parsed.title == "Toy Story 5")
        #expect(parsed.season == nil)
        #expect(!parsed.alternateTitles.contains("WEBRip"))
    }

    @Test func offersNoAlternativesForAPlainReleaseName() {
        #expect(MediaTitleParser.parse("Dune.Part.Two.2024.2160p.BluRay.x265").alternateTitles.isEmpty)
    }
}
