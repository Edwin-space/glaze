import Foundation
import GlazeCore
import Observation
import VLCKit

/// Playback state for the Apple TV player.
///
/// VLCKit rather than AVFoundation, because seven films in ten on the NAS this was
/// measured against are Matroska, which AVFoundation will not open at all
/// (`docs/22_apple_tv_v1_plan.md`). The Mac loads libvlc with `dlopen`; tvOS forbids
/// that, so this links VideoLAN's statically built framework instead.
@MainActor
@Observable
final class TVPlaybackModel {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var hasFailed = false

    /// Seconds a single press of the remote skips. Matches what tvOS apps do.
    static let skipInterval: TimeInterval = 10

    let player = VLCMediaPlayer()
    private var observer: PlayerObserver?

    func start(_ resource: NetworkMediaResource) {
        let media = VLCMedia(url: resource.playbackURL)
        player.media = media

        let observer = PlayerObserver(
            onState: { [weak self] state in
                Task { @MainActor in self?.update(state: state) }
            },
            onTime: { [weak self] in
                Task { @MainActor in self?.updateTime() }
            }
        )
        self.observer = observer
        player.delegate = observer

        player.play()
        isPlaying = true
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func skip(_ seconds: TimeInterval) {
        if seconds < 0 {
            player.jumpBackward(-seconds)
        } else {
            player.jumpForward(seconds)
        }
    }

    func stop() {
        player.stop()
        isPlaying = false
    }

    /// Adds a subtitle file the player did not find on its own, and selects it.
    func addSubtitle(_ url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    fileprivate func update(state: VLCMediaPlayerState) {
        isPlaying = player.isPlaying
        hasFailed = state == .error
    }

    fileprivate func updateTime() {
        currentTime = TimeInterval(player.time.intValue) / 1000
        if let length = player.media?.length.intValue {
            duration = TimeInterval(length) / 1000
        }
    }
}

/// VLCKit talks through an Objective-C delegate, which cannot be the `@Observable`
/// model itself without dragging `NSObject` conformance into it.
///
/// It calls back on **its own input thread**, not the main one. An earlier version
/// asserted the opposite and used `MainActor.assumeIsolated`, which trapped the moment
/// a film started playing — the first state change arrives from `input_thread_Events`.
/// The hop has to be real.
private final class PlayerObserver: NSObject, VLCMediaPlayerDelegate {
    private let onState: @Sendable (VLCMediaPlayerState) -> Void
    private let onTime: @Sendable () -> Void

    init(
        onState: @escaping @Sendable (VLCMediaPlayerState) -> Void,
        onTime: @escaping @Sendable () -> Void
    ) {
        self.onState = onState
        self.onTime = onTime
    }

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        onState(newState)
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        onTime()
    }
}
