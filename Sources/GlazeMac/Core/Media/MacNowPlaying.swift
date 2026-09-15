import Foundation
import MediaPlayer

/// The keyboard's ⏮ ⏯ ⏭ keys, Control Center, and AirPods.
///
/// Without this the media keys on a Mac keyboard went to whatever else had last played
/// sound — Music would start while a film was on screen — and the previous and next keys
/// did nothing for a folder of episodes at all. The phone already answers these.
@MainActor
final class MacNowPlaying {
    struct Handlers {
        var togglePlayPause: () -> Void
        var play: () -> Void
        var pause: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (TimeInterval) -> Void
    }

    private var isRegistered = false

    func register(_ handlers: Handlers) {
        unregister()
        let centre = MPRemoteCommandCenter.shared()

        centre.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in handlers.togglePlayPause() }
            return .success
        }
        centre.playCommand.addTarget { _ in
            Task { @MainActor in handlers.play() }
            return .success
        }
        centre.pauseCommand.addTarget { _ in
            Task { @MainActor in handlers.pause() }
            return .success
        }
        centre.nextTrackCommand.addTarget { _ in
            Task { @MainActor in handlers.next() }
            return .success
        }
        centre.previousTrackCommand.addTarget { _ in
            Task { @MainActor in handlers.previous() }
            return .success
        }
        centre.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in handlers.seek(position) }
            return .success
        }
        for command in [
            centre.togglePlayPauseCommand, centre.playCommand, centre.pauseCommand,
            centre.nextTrackCommand, centre.previousTrackCommand, centre.changePlaybackPositionCommand
        ] {
            command.isEnabled = true
        }
        isRegistered = true
    }

    func unregister() {
        guard isRegistered else { return }
        let centre = MPRemoteCommandCenter.shared()
        for command in [
            centre.togglePlayPauseCommand, centre.playCommand, centre.pauseCommand,
            centre.nextTrackCommand, centre.previousTrackCommand, centre.changePlaybackPositionCommand
        ] {
            command.removeTarget(nil)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        isRegistered = false
    }

    /// What Control Center shows. Also what makes macOS route the media keys here: an app
    /// that has not said what it is playing is not offered them.
    func update(title: String, elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
