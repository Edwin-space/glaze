import Foundation
import Testing
@testable import GlazeCore

@Suite struct PlaybackEngineRouterTests {
    private func networkResource(_ address: String) -> MediaResource {
        .network(
            NetworkMediaResource(
                serverID: "server",
                objectID: "80",
                playbackURL: URL(string: address)!
            )
        )
    }

    /// The case that stalled 4K playback: a DLNA address is an object id, so there is
    /// no extension to route on and AVKit was picked for an MKV it cannot open.
    @Test func sendsAStreamWithNoFileExtensionToVLC() {
        #expect(PlaybackEngineRouter.preferredEngine(for: networkResource("http://nas.local:50002/o/v/80")) == .nativeVLC)
        #expect(PlaybackEngineRouter.preferredEngine(for: URL(string: "http://nas.local:50002/o/v/80")!) == .nativeVLC)
    }

    @Test func sendsEveryStreamToVLCEvenWhenTheAddressLooksLikeAFile() {
        #expect(PlaybackEngineRouter.preferredEngine(for: networkResource("http://nas.local/Film.mp4")) == .nativeVLC)
        #expect(PlaybackEngineRouter.preferredEngine(for: networkResource("https://nas.local/Film.mkv")) == .nativeVLC)
    }

    @Test func keepsRoutingLocalFilesByContainer() {
        let mkv = URL(fileURLWithPath: "/Users/someone/Film.mkv")
        let unknown = URL(fileURLWithPath: "/Users/someone/Film.rmvb")
        #expect(PlaybackEngineRouter.preferredEngine(for: .localFile(mkv)) == .nativeVLC)
        #expect(PlaybackEngineRouter.preferredEngine(for: .localFile(unknown)) == .avkit)
    }

    /// A share mounted in Finder is a file URL and behaves like one.
    @Test func treatsAMountedShareAsALocalFile() {
        let mounted = URL(fileURLWithPath: "/Volumes/NAS/Movies/Film.mkv")
        #expect(PlaybackEngineRouter.preferredEngine(for: .localFile(mounted)) == .nativeVLC)
    }
}
