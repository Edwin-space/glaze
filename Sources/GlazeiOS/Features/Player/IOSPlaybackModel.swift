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
    /// What the rate was before a press-and-hold sped it up.
    private var heldFromRate: Float?
    /// Watches for the headphones going away.
    private var routeObserver: (any NSObjectProtocol)?

    /// Called once when the film plays to its end — not when it is stopped by hand, and
    /// not when it fails. The view decides whether that means the next file.
    var onFinished: (() -> Void)?
    /// Wired to the lock screen's and Control Center's track buttons, and to AirPods.
    /// Nil hides those buttons, which is right for a film with nothing around it.
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    /// Guards `onFinished` so a stopped player that keeps reporting `.stopped` does not
    /// skip through a whole folder.
    private var hasReportedFinish = false
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
        hasOpened = false
        lastNowPlaying = nil
        lastPositionWrite = .distantPast
        hasFailed = false
        isBuffering = true
        hasReportedFinish = false
        // A late `.stopped` from the film being left must not read as this one ending.
        // With no duration yet, the end check cannot pass.
        currentTime = 0
        duration = 0

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
        observeAudioRoute()
        player.play()
        player.rate = rate
    }

    /// Stops the film when the sound would otherwise move to the phone's own speaker.
    ///
    /// Taking an AirPod out is the ordinary case: the film used to carry on playing
    /// out loud, and by the time it was back in the viewer had missed a scene. The
    /// rule itself is `AudioRouteChange`, which is shared and tested.
    private func observeAudioRoute() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo
            let rawReason = info?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let previous = info?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let outputs = previous?.outputs.map(\.portType.rawValue) ?? []
            let unavailable = AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
            guard AudioRouteChange.shouldPause(
                reasonIsDeviceUnavailable: unavailable,
                previousOutputs: outputs
            ) else { return }

            // Hopped rather than asserted. The notification does arrive on the main
            // queue, but assuming an actor at a boundary like this is exactly what
            // trapped the process twice already (`docs/48`), and a runloop of delay
            // costs nothing here.
            Task { @MainActor [weak self] in
                guard let self, player.isPlaying else { return }
                player.pause()
                isPlaying = false
                updateNowPlaying()
            }
        }
    }

    // MARK: - Transport

    func togglePlayback() {
        if player.isPlaying { player.pause() } else { player.play() }
        isPlaying = player.isPlaying
        // Pausing is a moment someone may well walk away from, and the tick only
        // writes the position every few seconds now.
        rememberPosition()
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
        lastNowPlaying = nil
    }

    /// The film's shape, once VLC knows it. Nil until the first frame is decoded.
    var videoSize: CGSize? {
        let size = player.videoSize
        return size.width > 0 && size.height > 0 ? size : nil
    }

    /// Speeds playback up while a finger is held down, and puts it back afterwards.
    /// The rate the viewer chose is remembered separately, so letting go returns to
    /// 1.25× rather than to 1× if that is what they were watching at.
    func holdRate(_ multiplier: Float) {
        if heldFromRate == nil { heldFromRate = rate }
        player.rate = (heldFromRate ?? 1) * multiplier
    }

    func releaseHeldRate() {
        guard let heldFromRate else { return }
        self.heldFromRate = nil
        player.rate = heldFromRate
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
        // Stopped by hand is never "finished": the next film must not start by itself
        // because someone closed this one near its end.
        hasReportedFinish = true
        rememberPosition()
        player.stop()
        player.delegate = nil
        observer = nil
        releaseRemoteCommands()
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
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
        let lastTime = currentTime
        readState()
        // Tracks appear once, when the media is read, and change only when the film
        // does. Asking libVLC to enumerate them four times a second was both waste
        // and a main-thread call into a library whose input thread is busy pulling
        // bytes off the network.
        refreshTracks()

        // VLCKit 4 has no distinct "ended": a film that ran out is simply `.stopped`.
        // What separates it from a stop by hand is where the clock had got to, read
        // before `readState` resets it to zero.
        if state == .stopped, !hasReportedFinish, duration > 0,
           lastTime >= duration - Self.endTolerance {
            hasReportedFinish = true
            onFinished?()
        }
    }

    /// How close to the end still counts as the end. The last poll before stopping
    /// lands a second or two short, and a film that stops there has still finished.
    private static let endTolerance: TimeInterval = 3

    private func readState() {
        isPlaying = player.isPlaying

        // One `VLCMediaPlayer` serves every film, and until the new one is open it
        // still answers with the old one's clock. That is the knob that appears
        // somewhere in the middle of an unwatched film and then jumps to the start:
        // it was showing where the *previous* film had got to. Nothing is believed
        // until this media reports its own length.
        let length = player.media?.length.intValue ?? 0
        if length > 0 {
            duration = TimeInterval(length) / 1000
            hasOpened = true
        }
        guard hasOpened else {
            currentTime = pendingResume ?? 0
            return
        }

        currentTime = TimeInterval(player.time.intValue) / 1000
        applyResumeIfReady()
        chooseSubtitleIfReady()
        rememberPositionOccasionally()
        updateNowPlayingIfChanged()
    }

    /// Whether this film — not the one before it — has told us how long it is.
    private var hasOpened = false

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

    func refreshTracks() {
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

    /// Writing the position is two dictionaries read out of `UserDefaults`, changed
    /// and written back — the whole library's worth, every time. On the time tick
    /// that is four times a second for as long as the film runs, and it gets slower
    /// the more films someone has watched. Once every few seconds is as much as
    /// resuming needs.
    private func rememberPositionOccasionally() {
        let now = Date()
        guard now.timeIntervalSince(lastPositionWrite) >= Self.positionWriteInterval else { return }
        lastPositionWrite = now
        rememberPosition()
    }

    private static let positionWriteInterval: TimeInterval = 5
    private var lastPositionWrite = Date.distantPast

    func rememberPosition() {
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
        centre.nextTrackCommand.isEnabled = onNextTrack != nil
        centre.previousTrackCommand.isEnabled = onPreviousTrack != nil
        centre.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNextTrack?() }
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPreviousTrack?() }
            return .success
        }
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
            centre.changePlaybackPositionCommand,
            centre.nextTrackCommand, centre.previousTrackCommand
        ] {
            command.removeTarget(nil)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// The lock screen extrapolates elapsed time from the rate it was last given, so
    /// it only needs telling when something actually changes. Rebuilding the whole
    /// dictionary on the time tick was four cross-process writes a second that said
    /// the same thing.
    private func updateNowPlayingIfChanged() {
        let state = NowPlayingState(
            seconds: Int(currentTime),
            duration: Int(duration),
            isPlaying: isPlaying,
            rate: rate
        )
        guard state.isWorthSending(comparedTo: lastNowPlaying) else { return }
        lastNowPlaying = state
        updateNowPlaying()
    }

    private struct NowPlayingState: Equatable {
        var seconds: Int
        var duration: Int
        var isPlaying: Bool
        var rate: Float

        /// A second ticking by on its own is not news; the lock screen is already
        /// counting. Everything else is.
        func isWorthSending(comparedTo previous: NowPlayingState?) -> Bool {
            guard let previous else { return true }
            if duration != previous.duration { return true }
            if isPlaying != previous.isPlaying { return true }
            if rate != previous.rate { return true }
            // A jump means a seek, which the lock screen cannot have guessed.
            return abs(seconds - previous.seconds) > 2
        }
    }

    private var lastNowPlaying: NowPlayingState?

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
