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

    private let positions = PlaybackPositionStore()
    /// Applied once the stream reports a length; asking to seek before then is ignored.
    private var pendingSeek: TimeInterval?
    /// The subtitle the folder listing found beside the film, still to be selected.
    private var pendingSubtitleLanguage: String?
    private var hasChosenSubtitle = false

    /// - Parameter subtitleURL: a subtitle found sitting beside the film. Attached to
    ///   the media before it is played, which VLCKit requires — adding it afterwards
    ///   through `addPlaybackSlave` is ignored, and the film comes up showing whichever
    ///   track was embedded in the container instead.
    func start(
        _ resource: NetworkMediaResource,
        at startAt: TimeInterval = 0,
        subtitleURL: URL? = nil
    ) {
        let media = VLCMedia(url: resource.playbackURL)

        if let subtitleURL {
            // Priority 4 is VLC's "user selected". It gets the file loaded, but does
            // not make VLC show it: a film with a subtitle track inside it comes up
            // showing that one regardless, so the choice is made explicitly below once
            // the tracks exist.
            media?.addSlave(VLCMediaSlave(url: subtitleURL, type: .subtitle, priority: 4))
            pendingSubtitleLanguage = SubtitleFile.manual(url: subtitleURL).languageCode
            hasChosenSubtitle = false
        }

        player.media = media
        pendingSeek = startAt > 0 ? startAt : nil

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

        // A stream has no length until it has been opened and read a little; seeking
        // before that lands nowhere and is silently dropped.
        if let pendingSeek, duration > 0 {
            player.time = VLCTime(int: Int32(pendingSeek * 1000))
            self.pendingSeek = nil
        }

        chooseSubtitleIfReady()
    }

    /// Selects the subtitle that came from the folder rather than the one inside the
    /// film.
    ///
    /// Tracks do not exist until the media has been read, so this runs on the time
    /// updates and does its work once.
    private func chooseSubtitleIfReady() {
        guard !hasChosenSubtitle, pendingSubtitleLanguage != nil else { return }

        let tracks = player.textTracks
        guard !tracks.isEmpty else { return }

        // The slave is appended after whatever the container carried, so the last track
        // is it — but prefer a language match when the tracks say what they are, since
        // that survives a film that carries no subtitles at all.
        let chosen = tracks.first { track in
            guard let language = track.language, let wanted = pendingSubtitleLanguage else { return false }
            return SubtitleLanguageCode.normalized(language) == wanted
        } ?? tracks.last

        if let chosen {
            player.selectTextTracks([chosen])
        }

        hasChosenSubtitle = true
    }

    /// Stores where the viewer got to, so the shelf can offer to resume.
    func rememberPosition(for resource: NetworkMediaResource) {
        guard duration > 0 else { return }
        positions.record(currentTime, duration: duration, for: .network(resource))
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
