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
