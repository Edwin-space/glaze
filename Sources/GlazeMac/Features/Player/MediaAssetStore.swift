import Foundation
import GlazeCore
import Observation

@MainActor
@Observable
final class MediaAssetStore {
    var mediaInspection: MediaInspection?
    var isInspectingMedia = false
    var currentMediaAsset: MediaAsset?
    private let probeCoordinator = MediaProbeCoordinator.shared

    /// Resets media state for a newly loaded video. ffprobe is the primary source so
    /// MKV/VLC playback exposes the same real container information as AVKit media.
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

        inspect(url: url, engine: engine, resource: resource, isStillCurrent: isStillCurrent)
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

    private func inspect(
        url: URL,
        engine: PlaybackEngineKind,
        resource: MediaResource?,
        isStillCurrent: @escaping () -> Bool
    ) {
        Task {
            let inspection: MediaInspection
            do {
                inspection = try await probeCoordinator.probe(
                    url: url,
                    deferForPlayback: resource?.isNetwork == true
                ).inspection
            } catch {
                inspection = engine == .nativeVLC
                    ? MediaInspector.lightweightInspection(url: url, isPlayable: nil)
                    : await MediaInspector.inspect(url: url)
            }
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
