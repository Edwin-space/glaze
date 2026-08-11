import Foundation
import GlazeCore
import Observation

@MainActor
@Observable
final class MediaAssetStore {
    var mediaInspection: MediaInspection?
    var isInspectingMedia = false
    var currentMediaAsset: MediaAsset?

    /// Resets media state for a newly loaded video. Uses a lightweight, synchronous inspection for the
    /// native VLC engine (no AVFoundation track loading available) and a full async inspection for AVKit.
    func prepareForNewVideo(
        url: URL,
        hasDetectedSubtitles: Bool,
        engine: PlaybackEngineKind,
        resource: MediaResource? = nil,
        source: MediaLibrarySource = .localFolder,
        isStillCurrent: @escaping () -> Bool
    ) {
        mediaInspection = nil
        isInspectingMedia = true
        currentMediaAsset = makeAsset(
            for: url,
            resource: resource,
            source: source,
            hasSubtitles: hasDetectedSubtitles
        )

        if engine == .nativeVLC {
            mediaInspection = MediaInspector.lightweightInspection(url: url, isPlayable: nil)
            isInspectingMedia = false
        } else {
            inspect(url: url, isStillCurrent: isStillCurrent)
        }
    }

    func markSubtitleExternallyLoaded() {
        currentMediaAsset?.subtitleReadiness = .externalLoaded
    }

    func markSubtitleEmbeddedLoaded() {
        currentMediaAsset?.subtitleReadiness = .embeddedLoaded
    }

    func markSubtitleGenerated() {
        currentMediaAsset?.subtitleReadiness = .generated
    }

    private func inspect(url: URL, isStillCurrent: @escaping () -> Bool) {
        Task {
            let inspection = await MediaInspector.inspect(url: url)
            guard isStillCurrent() else {
                return
            }

            mediaInspection = inspection
            isInspectingMedia = false
        }
    }

    private func makeAsset(
        for url: URL,
        resource: MediaResource?,
        source: MediaLibrarySource,
        hasSubtitles: Bool
    ) -> MediaAsset {
        var asset = MediaAsset(resource: resource ?? .localFile(url), source: source)
        asset.subtitleReadiness = hasSubtitles ? .externalLoaded : .missing
        return asset
    }
}
