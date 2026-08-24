import AVKit
import GlazeCore
import SwiftUI

/// Plays one video from the NAS.
///
/// AVKit brings the transport, the scrubber, and the remote gestures people already
/// know from every other Apple TV app, so none of that is rebuilt here. What this adds
/// is telling the viewer when the file cannot be played at all — AVFoundation refuses
/// Matroska outright, and a NAS library is full of it. A black screen with a spinner
/// reads as a broken app; naming the format reads as a limit.
struct TVPlayerView: View {
    let resource: NetworkMediaResource

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failure: String?

    var body: some View {
        Group {
            if let failure {
                unplayable(failure)
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task { await start() }
        .onDisappear { player?.pause() }
    }

    private func start() async {
        let asset = AVURLAsset(url: resource.playbackURL)

        // Ask before playing rather than after failing. `isPlayable` is false for a
        // container AVFoundation will not open, which is the common case here.
        let playable = (try? await asset.load(.isPlayable)) ?? false
        guard playable else {
            failure = TVPlaybackSupport.describeUnsupported(resource)
            return
        }

        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player?.play()
    }

    private func unplayable(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(L10n.string("tv.playback.unsupported.title"))
                .font(.title2)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)
            Button(L10n.string("network.browser.back")) { dismiss() }
                .padding(.top, 12)
        }
    }
}

enum TVPlaybackSupport {
    /// Names the format when the server told us what it is, so the viewer knows which
    /// of their files this applies to rather than guessing.
    static func describeUnsupported(_ resource: NetworkMediaResource) -> String {
        let name = resource.mimeType?
            .split(separator: "/").last
            .map(String.init)?
            .uppercased()

        guard let name else { return L10n.string("tv.playback.unsupported.detail_generic") }
        return String(format: L10n.string("tv.playback.unsupported.detail_format"), name)
    }
}
