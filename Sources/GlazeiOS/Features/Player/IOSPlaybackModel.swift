import AVFoundation
import Foundation
import GlazeCore
import MediaPlayer
import Observation
import VLCKit

/// One selectable track — a subtitle or an audio language.
struct IOSTrackOption: Identifiable, Equatable {
    let id: String
    let title: String
    let languageCode: String?
    let isSelected: Bool
}

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
    /// True while the stream is opening or has run dry. A 4K remux over the network
    /// takes seconds to start, and a black screen with nothing on it reads as a crash.
    private(set) var isBuffering = true
    private(set) var hasFailed = false

    private(set) var subtitleTracks: [IOSTrackOption] = []
    private(set) var audioTracks: [IOSTrackOption] = []
    private(set) var subtitleDelay: TimeInterval = 0
    private(set) var subtitleScale: Float = 100
    private(set) var rate: Float = 1
    private(set) var isFillingScreen = false

    static let skipInterval: TimeInterval = 10
    static let rateOptions: [Float] = [0.75, 1, 1.25, 1.5, 2]

    let player = VLCMediaPlayer()

    private let positions = PlaybackPositionStore()
    private var resource: NetworkMediaResource?
    private var title = ""
    private var pendingResume: TimeInterval?
    private var observer: PlayerObserver?

    /// The language named by the subtitle file that came with the film, and the
    /// viewer's standing preference. Both are wanted before whatever the container
    /// happens to mark as selected.
    private var pendingSubtitleLanguage: String?
    private var preferredSubtitleLanguage: String?
    private var shouldAutomaticallySelectSubtitles = true
    private var hasChosenSubtitle = false

    // MARK: - Starting

    /// - Parameter subtitleURL: a subtitle found beside the film. It has to be attached
    ///   to the media *before* play; `addPlaybackSlave` afterwards is ignored and the
    ///   film comes up showing whichever track was baked into the container.
    func start(
        _ resource: NetworkMediaResource,
        title: String,
        at startAt: TimeInterval,
        subtitleURL: URL?,
        preferences: IOSUserPreferences
    ) {
        self.resource = resource
        self.title = title
        pendingResume = startAt > 0 ? startAt : positions.position(for: .network(resource))

        preferredSubtitleLanguage = SubtitleLanguageCode.normalized(preferences.defaultSubtitleLanguageCode)
        shouldAutomaticallySelectSubtitles = preferences.automaticallySelectSubtitles
        subtitleScale = preferences.subtitleScale
        rate = preferences.playbackRate
        hasChosenSubtitle = false
        hasFailed = false
        isBuffering = true

        let media = VLCMedia(url: resource.playbackURL)
        for option in MediaCachingPolicy.mediaOptions(for: resource.playbackURL) {
            media?.addOption(option)
        }
        if let subtitleURL {
            // Priority 4 is VLC's "user selected". It loads the file but does not show
            // it, so the choice is made explicitly once the tracks exist.
            media?.addSlave(VLCMediaSlave(url: subtitleURL, type: .subtitle, priority: 4))
            pendingSubtitleLanguage = SubtitleFile.manual(url: subtitleURL).languageCode
        }

        let observer = PlayerObserver(
            onState: { [weak self] state in Task { @MainActor in self?.apply(state) } },
            onTime: { [weak self] in Task { @MainActor in self?.readState() } },
            onBuffering: { [weak self] progress in
                // Reported as a fraction, not a percentage: a full cache arrives as
                // 1.0. Comparing against 100 left the spinner on top of a film that
                // was already playing.
                Task { @MainActor in self?.isBuffering = progress < 1 }
            }
        )
        self.observer = observer
        player.delegate = observer
        player.media = media
        player.currentSubTitleFontScale = SubtitleScale.fraction(fromPercent: subtitleScale)

        // The phone is often the only thing making sound, and playback has to survive
        // the screen locking.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        configureRemoteCommands()
        player.play()
        player.rate = rate
    }

    // MARK: - Transport

    func togglePlayback() {
        if player.isPlaying { player.pause() } else { player.play() }
        isPlaying = player.isPlaying
        updateNowPlaying()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func seek(to time: TimeInterval) {
        let ceiling = duration > 0 ? duration : .greatestFiniteMagnitude
        let target = min(max(time, 0), ceiling)
        player.time = VLCTime(int: Int32(target * 1000))
        currentTime = target
        updateNowPlaying()
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        player.rate = newRate
        updateNowPlaying()
    }

    /// Fit letterboxes the film; fill crops it to the edges of the phone.
    func setFillingScreen(_ filling: Bool) {
        isFillingScreen = filling
        player.videoFitMode = filling ? .larger : .smaller
    }

    func stop() {
        rememberPosition()
        player.stop()
        player.delegate = nil
        observer = nil
        releaseRemoteCommands()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Tracks

    func selectSubtitleTrack(id: String) {
        guard let track = player.textTracks.first(where: { $0.trackId == id }) else { return }
        player.selectTextTracks([track])
        // A choice made by hand must not be overwritten by the automatic one.
        hasChosenSubtitle = true
        refreshTracks()
    }

    func disableSubtitles() {
        player.deselectAllTextTracks()
        hasChosenSubtitle = true
        refreshTracks()
    }

    func selectAudioTrack(id: String) {
        guard let track = player.audioTracks.first(where: { $0.trackId == id }) else { return }
        track.isSelectedExclusively = true
        refreshTracks()
    }

    /// Attaches a subtitle the player never found on its own — the file whose name does
    /// not match the film's.
    func addSubtitle(_ url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
        hasChosenSubtitle = true
    }

    func adjustSubtitleDelay(by seconds: TimeInterval) {
        let next = min(max(subtitleDelay + seconds, -10), 10)
        player.currentVideoSubTitleDelay = Int(next * 1_000_000)
        subtitleDelay = next
    }

    func setSubtitleScale(_ scale: Float) {
        let next = SubtitleScale.clampPercent(scale)
        player.currentSubTitleFontScale = SubtitleScale.fraction(fromPercent: next)
        subtitleScale = next
    }


    // MARK: - State

    private func apply(_ state: VLCMediaPlayerState) {
        isPlaying = player.isPlaying
        hasFailed = state == .error
        // There is no buffering state in VLCKit 4 — a stall is reported through
        // `mediaPlayerBufferingChanged` instead. Opening is the one state that means
        // "nothing on screen yet".
        switch state {
        case .opening:
            isBuffering = true
        case .playing, .paused, .stopped, .stopping, .error:
            isBuffering = false
        default:
            break
        }
        readState()
    }

    private func readState() {
        isPlaying = player.isPlaying
        currentTime = TimeInterval(player.time.intValue) / 1000
        if let length = player.media?.length.intValue, length > 0 {
            duration = TimeInterval(length) / 1000
        }
        applyResumeIfReady()
        chooseSubtitleIfReady()
        refreshTracks()
        rememberPosition()
        updateNowPlaying()
    }

    /// Seeking before the media is open is dropped, so the resume waits for the clock
    /// to start moving and is applied once.
    private func applyResumeIfReady() {
        guard let resume = pendingResume, duration > 0, currentTime > 0 else { return }
        pendingResume = nil
        guard resume < duration else { return }
        seek(to: resume)
    }

    /// Picks the subtitle the viewer would have picked. Tracks do not exist until the
    /// media has been read, so this runs on the time updates and does its work once.
    private func chooseSubtitleIfReady() {
        guard !hasChosenSubtitle, shouldAutomaticallySelectSubtitles else { return }
        let tracks = player.textTracks
        guard !tracks.isEmpty else { return }

        let chosen = tracks.first { matches($0, preferredSubtitleLanguage) }
            ?? tracks.first { matches($0, pendingSubtitleLanguage) }
            ?? tracks.first(where: \.isSelected)
            ?? tracks.first
        if let chosen { player.selectTextTracks([chosen]) }
        hasChosenSubtitle = true
    }

    private func matches(_ track: VLCMediaPlayer.Track, _ wanted: String?) -> Bool {
        guard let wanted, let language = track.language else { return false }
        return SubtitleLanguageCode.normalized(language) == wanted
    }

    private func refreshTracks() {
        subtitleTracks = player.textTracks.map(Self.option(for:))
        audioTracks = player.audioTracks.map(Self.option(for:))
        subtitleDelay = TimeInterval(player.currentVideoSubTitleDelay) / 1_000_000
        let reportedScale = SubtitleScale.percent(fromFraction: player.currentSubTitleFontScale)
        if reportedScale > 0 { subtitleScale = reportedScale }
    }

    private static func option(for track: VLCMediaPlayer.Track) -> IOSTrackOption {
        let normalized = track.language.flatMap(SubtitleLanguageCode.normalized)
        let localized = normalized.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
        let name = track.trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return IOSTrackOption(
            id: track.trackId,
            title: localized ?? (name.isEmpty ? L10n.string("tv.player.subtitle.unknown") : name),
            languageCode: normalized,
            isSelected: track.isSelected
        )
    }

    private func rememberPosition() {
        // Held while a resume is still waiting: playback starts at zero, and a
        // near-zero position clears the very value about to be seeked to.
        guard pendingResume == nil, let resource, duration > 0 else { return }
        positions.record(currentTime, duration: duration, for: .network(resource))
    }

    // MARK: - Lock screen

    /// Background audio is declared in the Info.plist, but iOS only keeps a session
    /// alive — and only draws lock-screen controls — for an app that says what is
    /// playing and answers the transport commands.
    private func configureRemoteCommands() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.isEnabled = true
        centre.pauseCommand.isEnabled = true
        centre.togglePlayPauseCommand.isEnabled = true
        centre.skipForwardCommand.isEnabled = true
        centre.skipBackwardCommand.isEnabled = true
        centre.changePlaybackPositionCommand.isEnabled = true
        centre.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        centre.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]

        centre.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.player.isPlaying else { return }
                self.togglePlayback()
            }
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player.isPlaying else { return }
                self.togglePlayback()
            }
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        centre.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: IOSPlaybackModel.skipInterval) }
            return .success
        }
        centre.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -IOSPlaybackModel.skipInterval) }
            return .success
        }
        centre.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let target = event.positionTime
            Task { @MainActor in self?.seek(to: target) }
            return .success
        }
    }

    private func releaseRemoteCommands() {
        let centre = MPRemoteCommandCenter.shared()
        for command in [
            centre.playCommand, centre.pauseCommand, centre.togglePlayPauseCommand,
            centre.skipForwardCommand, centre.skipBackwardCommand,
            centre.changePlaybackPositionCommand
        ] {
            command.removeTarget(nil)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0
        ]
    }
}

/// VLCKit talks through an Objective-C delegate, which cannot be the `@Observable`
/// model itself without dragging `NSObject` conformance into it.
///
/// It calls back on **its own input thread**, not the main one, so every hop here is
/// real. The state callback takes a `VLCMediaPlayerState`, not a `Notification`: an
/// earlier version of this file declared the notification form, which is a different
/// selector, so it was never called and errors went unseen.
private final class PlayerObserver: NSObject, VLCMediaPlayerDelegate {
    private let onState: @Sendable (VLCMediaPlayerState) -> Void
    private let onTime: @Sendable () -> Void
    private let onBuffering: @Sendable (Float) -> Void

    init(
        onState: @escaping @Sendable (VLCMediaPlayerState) -> Void,
        onTime: @escaping @Sendable () -> Void,
        onBuffering: @escaping @Sendable (Float) -> Void
    ) {
        self.onState = onState
        self.onTime = onTime
        self.onBuffering = onBuffering
    }

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        onState(newState)
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        onTime()
    }

    func mediaPlayerBufferingChanged(_ progress: Float) {
        onBuffering(progress)
    }
}
