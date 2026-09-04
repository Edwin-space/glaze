import Foundation
import Testing
@testable import GlazeCore

@Suite struct MediaCachingPolicyTests {
    @Test func givesAStreamABufferItCanSurviveAHiccupWith() {
        let stream = URL(string: "http://nas.local:50002/o/v/73.mkv")!
        #expect(MediaCachingPolicy.isRemote(stream))
        #expect(MediaCachingPolicy.cachingMilliseconds(for: stream) == 3_000)
    }

    /// The case that was being missed: a share mounted in Finder is a file URL, but the
    /// bytes still cross the network.
    @Test func treatsAMountedShareAsRemote() {
        let mounted = URL(fileURLWithPath: "/Volumes/emby/Video/Movie/Dune.mkv")
        #expect(MediaCachingPolicy.isRemote(mounted))
        #expect(MediaCachingPolicy.cachingMilliseconds(for: mounted) == 3_000)
    }

    @Test func leavesAFileOnTheBootVolumeAlone() {
        let local = URL(fileURLWithPath: "/Users/edwin/Movies/Film.mkv")
        #expect(!MediaCachingPolicy.isRemote(local))
        #expect(MediaCachingPolicy.cachingMilliseconds(for: local) == 300)
    }

    @Test func writesTheOptionFormsLibVLCTakes() {
        let stream = URL(string: "https://nas.local/Film.mkv")!
        #expect(MediaCachingPolicy.mediaOptions(for: stream) == [":file-caching=3000", ":network-caching=3000"])
    }
}
