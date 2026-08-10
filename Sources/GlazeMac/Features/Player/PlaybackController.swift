import AVKit
import GlazeCore
import Observation

@MainActor
@Observable
final class PlaybackController {
    var player: AVPlayer?
    var activePlaybackEngine: PlaybackEngineKind = .none
    var currentVideoURL: URL?
    var currentPlaybackURL: URL?
    var errorMessage: String?
    var isPreparingCompatibilityPlayback = false

    /// Fired on every periodic time update so other controllers (subtitles) can react without owning the player.
    var onTimeUpdate: ((TimeInterval) -> Void)?
    /// Fired when a playback failure can't be auto-recovered via compatibility remux, so the view can surface it.
    var onPlaybackFailureNeedsAttention: (() -> Void)?
    /// Fired when a compatibility remux succeeds, so the view can re-run the full "load new video" orchestration.
    var onCompatibilityRemuxSucceeded: ((_ originalURL: URL, _ remuxedURL: URL) -> Void)?

    private var compatibilityAttemptedPaths: Set<String> = []
    private var compatibilityTask: Task<Void, Never>?
    private var playbackSessionID = UUID()
    private var timeObserver: Any?
    private var observedPlayer: AVPlayer?
    private var itemStatusObserver: NSKeyValueObservation?
    private var playerTimeControlObserver: NSKeyValueObservation?

    func loadWithNativeEngine(_ url: URL) {
        beginNewPlaybackSession()
        player = nil
        activePlaybackEngine = .nativeVLC
        currentVideoURL = url
        currentPlaybackURL = nil
        errorMessage = nil
    }

    func loadWithAVKit(originalURL: URL, playbackURL: URL, shouldStartPlayback: Bool) {
        beginNewPlaybackSession()

        let item = AVPlayerItem(url: playbackURL)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        activePlaybackEngine = .avkit
        currentVideoURL = originalURL
        currentPlaybackURL = playbackURL
        errorMessage = nil
        isPreparingCompatibilityPlayback = false
        installPlaybackObservers(on: nextPlayer, item: item, shouldStartPlayback: shouldStartPlayback)
    }

    func beginNewPlaybackSession() {
        playbackSessionID = UUID()
        compatibilityTask?.cancel()
        compatibilityTask = nil
        removeTimeObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        activePlaybackEngine = .none
        isPreparingCompatibilityPlayback = false
    }

    func stopForWindowClose() {
        compatibilityTask?.cancel()
        compatibilityTask = nil
        removeTimeObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        observedPlayer = nil
        activePlaybackEngine = .none
        isPreparingCompatibilityPlayback = false
    }

    var isCurrentContainerKnownCompatibilityRisk: Bool {
        guard let currentVideoURL else {
            return false
        }

        return PlaybackEngineRouter.nativeEngineContainers.contains(currentVideoURL.pathExtension.lowercased())
    }

    private func installPlaybackObservers(on player: AVPlayer, item: AVPlayerItem, shouldStartPlayback: Bool) {
        installTimeObserver(on: player)
        installItemStatusObserver(on: item, player: player, shouldStartPlayback: shouldStartPlayback)
        installTimeControlObserver(on: player)
    }

    private func installItemStatusObserver(on item: AVPlayerItem, player: AVPlayer, shouldStartPlayback: Bool) {
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                guard let self, player.currentItem === observedItem else {
                    return
                }

                switch observedItem.status {
                case .readyToPlay:
                    self.errorMessage = nil
                    if shouldStartPlayback {
                        player.play()
                    }
                case .failed:
                    self.handlePlaybackFailure(error: observedItem.error)
                case .unknown:
                    break
                @unknown default:
                    self.errorMessage = L10n.string("player.error.playback_failed")
                }
            }
        }
    }

    private func installTimeControlObserver(on player: AVPlayer) {
        playerTimeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor in
                guard let self, self.player === observedPlayer else {
                    return
                }

                if observedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate,
                   let reason = observedPlayer.reasonForWaitingToPlay {
                    self.errorMessage = self.playbackWaitingMessage(for: reason)
                } else if observedPlayer.timeControlStatus == .playing {
                    self.errorMessage = nil
                }
            }
        }
    }

    private func installTimeObserver(on player: AVPlayer) {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.onTimeUpdate?(time.seconds)
            }
        }
        observedPlayer = player
    }

    private func removeTimeObserver() {
        itemStatusObserver?.invalidate()
        playerTimeControlObserver?.invalidate()
        itemStatusObserver = nil
        playerTimeControlObserver = nil

        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }

        timeObserver = nil
        observedPlayer = nil
    }

    private func playbackWaitingMessage(for reason: AVPlayer.WaitingReason) -> String {
        switch reason {
        case .evaluatingBufferingRate:
            L10n.string("player.status.buffering")
        case .toMinimizeStalls:
            L10n.string("player.status.waiting")
        case .noItemToPlay:
            L10n.string("player.error.playback_failed")
        default:
            L10n.string("player.status.waiting")
        }
    }

    private func playbackFailureMessage(for error: Error?) -> String {
        if isCurrentContainerKnownCompatibilityRisk {
            return L10n.string("player.error.compatibility_required")
        }

        return error?.localizedDescription ?? L10n.string("player.error.playback_failed")
    }

    private func handlePlaybackFailure(error: Error?) {
        guard let currentVideoURL else {
            errorMessage = playbackFailureMessage(for: error)
            return
        }

        if isCurrentContainerKnownCompatibilityRisk,
           currentPlaybackURL?.path == currentVideoURL.path,
           !compatibilityAttemptedPaths.contains(currentVideoURL.path) {
            prepareCompatibilityPlayback(for: currentVideoURL)
            return
        }

        errorMessage = playbackFailureMessage(for: error)
        onPlaybackFailureNeedsAttention?()
    }

    private func prepareCompatibilityPlayback(for originalURL: URL) {
        let sessionID = playbackSessionID
        compatibilityAttemptedPaths.insert(originalURL.path)
        isPreparingCompatibilityPlayback = true
        errorMessage = L10n.string("player.status.preparing_compatibility")

        compatibilityTask?.cancel()
        compatibilityTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let remuxedURL = try await FFmpegRemuxer.remuxForAVPlayer(inputURL: originalURL)
                guard !Task.isCancelled else {
                    return
                }

                guard self.playbackSessionID == sessionID,
                      self.currentVideoURL?.path == originalURL.path else {
                    return
                }

                self.compatibilityTask = nil
                self.onCompatibilityRemuxSucceeded?(originalURL, remuxedURL)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                guard self.playbackSessionID == sessionID,
                      self.currentVideoURL?.path == originalURL.path else {
                    return
                }

                self.compatibilityTask = nil
                self.isPreparingCompatibilityPlayback = false
                self.errorMessage = self.compatibilityFailureMessage(for: error)
                self.onPlaybackFailureNeedsAttention?()
            }
        }
    }

    private func compatibilityFailureMessage(for error: Error) -> String {
        guard let remuxError = error as? FFmpegRemuxer.RemuxError else {
            return L10n.string("player.error.compatibility_failed")
        }

        switch remuxError {
        case .toolUnavailable:
            return L10n.string("player.error.ffmpeg_unavailable")
        case .unsupportedVideoCodec:
            return L10n.string("player.error.unsupported_video_codec")
        case .failed(let failures):
            if failures.contains(where: { $0.mode == .audioAAC }) {
                return L10n.string("player.error.compatibility_transcode_failed")
            }
            return L10n.string("player.error.compatibility_failed")
        }
    }
}
