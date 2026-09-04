import Foundation
import GlazeCore
import Observation
import VLCKit

struct TVSubtitleTrackOption: Identifiable, Equatable {
    let id: String
    let title: String
    let languageCode: String?
    let isSelected: Bool
}

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
    private(set) var subtitleTracks: [TVSubtitleTrackOption] = []
    private(set) var selectedSubtitleTrackID: String?
    private(set) var subtitleDelay: TimeInterval = 0
    private(set) var subtitleScale: Float = 100

    /// Seconds a single press of the remote skips. Matches what tvOS apps do.
    static let skipInterval: TimeInterval = 10

    let player = VLCMediaPlayer()
    private var observer: PlayerObserver?

    private let positions = PlaybackPositionStore()
    /// Applied once the stream reports a length; asking to seek before then is ignored.
    private var pendingSeek: TimeInterval?
    /// The subtitle the folder listing found beside the film, still to be selected.
    private var pendingSubtitleLanguage: String?
    private var preferredSubtitleLanguage: String?
    private var shouldAutomaticallySelectSubtitles = true
    private var hasChosenSubtitle = false

    /// - Parameter subtitleURL: a subtitle found sitting beside the film. Attached to
    ///   the media before it is played, which VLCKit requires — adding it afterwards
    ///   through `addPlaybackSlave` is ignored, and the film comes up showing whichever
    ///   track was embedded in the container instead.
    func start(
        _ resource: NetworkMediaResource,
        at startAt: TimeInterval = 0,
        subtitleURL: URL? = nil,
        preferredSubtitleLanguageCode: String? = nil,
        automaticallySelectSubtitles: Bool = true,
        preferredSubtitleScale: Float = 100
    ) {
        let media = VLCMedia(url: resource.playbackURL)
        // Apple TV was left on VLCKit's default buffer, which a 4K remux over the
        // network outruns — see `MediaCachingPolicy`.
        for option in MediaCachingPolicy.mediaOptions(for: resource.playbackURL) {
            media?.addOption(option)
        }

        preferredSubtitleLanguage = preferredSubtitleLanguageCode.flatMap(SubtitleLanguageCode.normalized)
        shouldAutomaticallySelectSubtitles = automaticallySelectSubtitles
        subtitleScale = preferredSubtitleScale
        hasChosenSubtitle = false

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
        player.currentSubTitleFontScale = preferredSubtitleScale
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

    func seek(to seconds: TimeInterval) {
        guard duration > 0 else { return }
        let target = min(max(seconds, 0), duration)
        player.time = VLCTime(int: Int32(target * 1_000))
        currentTime = target
    }

    func stop() {
        player.stop()
        isPlaying = false
    }

    /// Adds a subtitle file the player did not find on its own, and selects it.
    func addSubtitle(_ url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    func selectSubtitleTrack(id: String) {
        guard let track = player.textTracks.first(where: { $0.trackId == id }) else { return }
        player.selectTextTracks([track])
        refreshSubtitleState()
    }

    func disableSubtitles() {
        player.deselectAllTextTracks()
        refreshSubtitleState()
    }

    func adjustSubtitleDelay(by seconds: TimeInterval) {
        let next = min(max(subtitleDelay + seconds, -10), 10)
        player.currentVideoSubTitleDelay = Int(next * 1_000_000)
        subtitleDelay = next
    }

    func setSubtitleScale(_ scale: Float) {
        let next = min(max(scale, 75), 160)
        player.currentSubTitleFontScale = next
        subtitleScale = next
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
        refreshSubtitleState()
    }

    /// Selects the subtitle that came from the folder rather than the one inside the
    /// film.
    ///
    /// Tracks do not exist until the media has been read, so this runs on the time
    /// updates and does its work once.
    private func chooseSubtitleIfReady() {
        guard !hasChosenSubtitle, shouldAutomaticallySelectSubtitles else { return }

        let tracks = player.textTracks
        guard !tracks.isEmpty else { return }

        // The viewer's saved reading language wins. A sidecar found beside the film is
        // next, then the track already marked as selected by the container/player.
        let chosen = tracks.first { track in
            guard let language = track.language, let wanted = preferredSubtitleLanguage else { return false }
            return SubtitleLanguageCode.normalized(language) == wanted
        } ?? tracks.first { track in
            guard let language = track.language, let wanted = pendingSubtitleLanguage else { return false }
            return SubtitleLanguageCode.normalized(language) == wanted
        } ?? tracks.first(where: \.isSelected)
        ?? tracks.first

        if let chosen {
            player.selectTextTracks([chosen])
        }

        hasChosenSubtitle = true
    }

    private func refreshSubtitleState() {
        let tracks = player.textTracks
        subtitleTracks = tracks.map { track in
            let normalizedLanguage = track.language.flatMap(SubtitleLanguageCode.normalized)
            let localizedLanguage = normalizedLanguage.flatMap {
                Locale.current.localizedString(forLanguageCode: $0)
            }
            let name = track.trackName.trimmingCharacters(in: .whitespacesAndNewlines)
            return TVSubtitleTrackOption(
                id: track.trackId,
                title: localizedLanguage ?? (name.isEmpty ? L10n.string("tv.player.subtitle.unknown") : name),
                languageCode: normalizedLanguage,
                isSelected: track.isSelected
            )
        }
        selectedSubtitleTrackID = subtitleTracks.first(where: \.isSelected)?.id
        subtitleDelay = TimeInterval(player.currentVideoSubTitleDelay) / 1_000_000
        let reportedScale = player.currentSubTitleFontScale
        if reportedScale > 0 {
            subtitleScale = reportedScale
        }
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
