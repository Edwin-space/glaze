import AVFoundation
import Foundation
import GlazeCore
import Observation
import VLCKit

/// Playback on a phone, through the same engine as the television.
///
/// VLCKit rather than AVPlayer for the same reason as everywhere else: a NAS holds
/// MKV, and AVFoundation does not open it. The buffer is sized by
/// `MediaCachingPolicy`, which is what keeps a 4K stream from stalling on the way in.
@Observable
@MainActor
final class IOSPlaybackModel {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var subtitleText = ""

    let player = VLCMediaPlayer()

    private let positions = PlaybackPositionStore()
    private var resource: NetworkMediaResource?
    private var pendingResume: TimeInterval?
    private var delegate: PlaybackDelegate?

    func start(_ resource: NetworkMediaResource, at startAt: TimeInterval, subtitleURL: URL?) {
        self.resource = resource
        pendingResume = startAt > 0 ? startAt : positions.position(for: .network(resource))

        let media = VLCMedia(url: resource.playbackURL)
        for option in MediaCachingPolicy.mediaOptions(for: resource.playbackURL) {
            media?.addOption(option)
        }
        if let subtitleURL {
            // Loading a subtitle is not the same as showing it; a film with a track
            // inside it comes up showing that one regardless.
            media?.addSlave(VLCMediaSlave(url: subtitleURL, type: .subtitle, priority: 4))
        }

        let delegate = PlaybackDelegate { [weak self] in self?.readState() }
        self.delegate = delegate
        player.delegate = delegate
        player.media = media

        // The phone is often the only thing making sound, and playback has to survive
        // the screen locking.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        player.play()
    }

    func togglePlayback() {
        if player.isPlaying { player.pause() } else { player.play() }
        isPlaying = player.isPlaying
    }

    func skip(by seconds: TimeInterval) {
        let target = max(0, min(currentTime + seconds, duration > 0 ? duration : .greatestFiniteMagnitude))
        seek(to: target)
    }

    func seek(to time: TimeInterval) {
        player.time = VLCTime(int: Int32(time * 1000))
        currentTime = time
    }

    func stop() {
        rememberPosition()
        player.stop()
        player.delegate = nil
        delegate = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func readState() {
        isPlaying = player.isPlaying
        currentTime = TimeInterval(player.time.intValue) / 1000
        if let length = player.media?.length.intValue, length > 0 {
            duration = TimeInterval(length) / 1000
        }
        applyResumeIfReady()
        rememberPosition()
    }

    /// Seeking before the media is open is dropped, so the resume waits for the clock
    /// to start moving and is applied once.
    private func applyResumeIfReady() {
        guard let resume = pendingResume, duration > 0, currentTime > 0 else { return }
        guard resume < duration else {
            pendingResume = nil
            return
        }
        pendingResume = nil
        seek(to: resume)
    }

    private func rememberPosition() {
        // Held while a resume is still waiting: playback starts at zero, and a
        // near-zero position clears the very value about to be seeked to.
        guard pendingResume == nil, let resource, duration > 0 else { return }
        positions.record(currentTime, duration: duration, for: .network(resource))
    }
}

/// VLCKit calls back on its own thread, so nothing here may touch the model directly.
///
/// The closure is captured as a `@Sendable` value rather than through `self`, because
/// hopping to the main actor from a delegate method would otherwise carry the delegate
/// across with it.
private final class PlaybackDelegate: NSObject, VLCMediaPlayerDelegate {
    private let onChange: @Sendable @MainActor () -> Void

    init(onChange: @escaping @Sendable @MainActor () -> Void) {
        self.onChange = onChange
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        let onChange = onChange
        Task { @MainActor in onChange() }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let onChange = onChange
        Task { @MainActor in onChange() }
    }
}
