import GlazeCore
import AppKit
import Observation
import SwiftUI

struct NativeVLCSurfaceView: NSViewRepresentable {
    let url: URL
    let session: NativeVLCPlaybackSession
    let onFailure: (String) -> Void

    func makeNSView(context: Context) -> NativeVLCPlayerView {
        let view = NativeVLCPlayerView()
        view.onFailure = onFailure
        session.attach(view)
        view.load(url)
        return view
    }

    func updateNSView(_ view: NativeVLCPlayerView, context: Context) {
        view.onFailure = onFailure
        session.attach(view)
        view.load(url)
    }

    static func dismantleNSView(_ nsView: NativeVLCPlayerView, coordinator: ()) {
        nsView.session?.detach(nsView)
        nsView.stopPlayback()
    }
}

@MainActor
@Observable
final class NativeVLCPlaybackSession {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var volume: Double = 1
    var onTimeUpdate: ((TimeInterval) -> Void)?
    /// Fired once when the media reaches its end, so the playlist can advance.
    /// AVKit gets this from AVPlayerItemDidPlayToEndTime; the VLC path has to poll for it.
    var onPlaybackEnded: (() -> Void)?

    fileprivate weak var playerView: NativeVLCPlayerView?

    func attach(_ view: NativeVLCPlayerView) {
        guard playerView !== view else { return }
        playerView = view
        view.session = self
    }

    func detach(_ view: NativeVLCPlayerView) {
        guard playerView === view else { return }
        playerView = nil
        reset()
    }

    func togglePlayback() {
        playerView?.setPaused(isPlaying)
    }

    func seek(to time: TimeInterval) {
        playerView?.seek(to: time)
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        playerView?.setVolume(volume)
    }

    fileprivate func update(isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval, volume: Double) {
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
        self.volume = volume
        onTimeUpdate?(currentTime)
    }

    fileprivate func reportPlaybackEnded() {
        onPlaybackEnded?()
    }

    fileprivate func reset() {
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}

@MainActor
final class NativeVLCPlayerView: NSView {
    var onFailure: ((String) -> Void)?
    weak var session: NativeVLCPlaybackSession?

    private var library: NativeVLCLibrary?
    private var player: NativeVLCLibrary.MediaPlayerHandle?
    private var loadedURL: URL?
    private var securityScopedURL: URL?
    private var progressTask: Task<Void, Never>?
    /// The end state persists while the player sits on the finished media, so the
    /// callback has to be latched to fire once rather than on every poll.
    private var hasReportedEnd = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    func load(_ url: URL) {
        guard loadedURL != url else {
            return
        }

        stopCurrentMedia()
        hasReportedEnd = false
        loadedURL = url
        if url.isFileURL, url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }

        let library: NativeVLCLibrary
        do {
            library = try NativeVLCLibrary.shared()
        } catch {
            loadedURL = nil
            releasePlaybackResources()
            onFailure?(error.localizedDescription)
            return
        }

        guard let instance = library.sharedPlaybackInstance() else {
            loadedURL = nil
            releasePlaybackResources()
            onFailure?("Unable to create libVLC instance")
            assertionFailure("Unable to create libVLC instance")
            return
        }

        guard let player = reusablePlayer(using: library, instance: instance) else {
            loadedURL = nil
            releaseSecurityScopedURL()
            onFailure?("Unable to create libVLC media player")
            assertionFailure("Unable to create libVLC media player")
            return
        }

        let media = url.isFileURL
            ? url.path.withCString { library.newMediaPath(instance, $0) }
            : url.absoluteString.withCString { library.newMediaLocation(instance, $0) }
        guard let media else {
            loadedURL = nil
            releaseSecurityScopedURL()
            onFailure?("Unable to create libVLC media")
            assertionFailure("Unable to create libVLC media")
            return
        }

        // Sized to where the film is coming from — see `MediaCachingPolicy`. A fixed
        // small buffer stalled 4K over the network and made seeking unusable.
        (MediaCachingPolicy.mediaOptions(for: url) + [
            ":no-sub-autodetect-file",
            // Glaze draws subtitles itself — it has to, to show a translation, or an
            // original and a translation together, in its own styling. Left to its own
            // devices VLC also renders any subtitle track embedded in the container,
            // and the two land on top of each other: a film with a built-in track came
            // up with the same line drawn twice, once by each.
            ":no-spu",
            ":avcodec-fast"
        ]).forEach { option in
            option.withCString { library.addMediaOption(media, $0) }
        }

        library.setMedia(player, media)
        library.releaseMedia(media)
        _ = library.play(player)

        self.library = library
        setVolume(session?.volume ?? 1)
        startProgressUpdates()
    }

    func stopPlayback() {
        releasePlaybackResources()
    }

    func setPaused(_ paused: Bool) {
        guard let library, let player else { return }
        library.setPause(player, paused ? 1 : 0)
        updateSession()
    }

    func seek(to time: TimeInterval) {
        guard let library, let player else { return }
        _ = library.setTime(player, Int64(max(time, 0) * 1_000))
        updateSession()
    }

    func setVolume(_ volume: Double) {
        guard let library, let player else { return }
        _ = library.setVolume(player, Int32(min(max(volume, 0), 1) * 100))
        updateSession()
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateSession()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func updateSession() {
        guard let library, let player else { return }
        let currentTime = max(TimeInterval(library.getTime(player)) / 1_000, 0)
        let duration = max(TimeInterval(library.getLength(player)) / 1_000, 0)
        let volume = max(Double(library.getVolume(player)) / 100, 0)
        session?.update(
            isPlaying: library.isPlaying(player) != 0,
            currentTime: currentTime,
            duration: duration,
            volume: volume
        )

        let state = NativeVLCLibrary.PlayerState(rawValue: library.getState(player))
        if state == .ended {
            guard !hasReportedEnd else { return }
            hasReportedEnd = true
            session?.reportPlaybackEnded()
        } else if state == .playing || state == .opening {
            // Re-arm for the next item once playback has genuinely restarted.
            hasReportedEnd = false
        }
    }

    private func reusablePlayer(using library: NativeVLCLibrary, instance: NativeVLCLibrary.InstanceHandle) -> NativeVLCLibrary.MediaPlayerHandle? {
        if let player {
            return player
        }

        guard let player = library.newPlayer(instance) else {
            return nil
        }

        library.setNSObject(player, Unmanaged.passUnretained(self).toOpaque())
        self.player = player
        return player
    }

    private func stopCurrentMedia() {
        progressTask?.cancel()
        progressTask = nil
        if let library, let player {
            library.stop(player)
            library.setMedia(player, nil)
        }

        releaseSecurityScopedURL()
        loadedURL = nil
        session?.reset()
    }

    private func releasePlaybackResources() {
        progressTask?.cancel()
        progressTask = nil
        if let library {
            if let player {
                library.stop(player)
                library.setMedia(player, nil)
                library.releasePlayer(player)
                self.player = nil
            }

        }

        releaseSecurityScopedURL()
        loadedURL = nil
        self.library = nil
        session?.reset()
    }

    private func releaseSecurityScopedURL() {
        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
            self.securityScopedURL = nil
        }
    }
}
