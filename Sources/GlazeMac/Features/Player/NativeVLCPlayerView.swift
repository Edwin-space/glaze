import AppKit
import SwiftUI

struct NativeVLCSurfaceView: NSViewRepresentable {
    let url: URL
    let onFailure: (String) -> Void

    func makeNSView(context: Context) -> NativeVLCPlayerView {
        let view = NativeVLCPlayerView()
        view.onFailure = onFailure
        view.load(url)
        return view
    }

    func updateNSView(_ view: NativeVLCPlayerView, context: Context) {
        view.onFailure = onFailure
        view.load(url)
    }

    static func dismantleNSView(_ nsView: NativeVLCPlayerView, coordinator: ()) {
        nsView.stopPlayback()
    }
}

final class NativeVLCPlayerView: NSView {
    var onFailure: ((String) -> Void)?

    private var library: NativeVLCLibrary?
    private var player: NativeVLCLibrary.MediaPlayerHandle?
    private var loadedURL: URL?
    private var securityScopedURL: URL?

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
        loadedURL = url
        if url.startAccessingSecurityScopedResource() {
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

        guard let media = url.path.withCString({ library.newMediaPath(instance, $0) }) else {
            loadedURL = nil
            releaseSecurityScopedURL()
            onFailure?("Unable to create libVLC media")
            assertionFailure("Unable to create libVLC media")
            return
        }

        [
            ":file-caching=100",
            ":network-caching=300",
            ":no-sub-autodetect-file",
            ":avcodec-fast"
        ].forEach { option in
            option.withCString { library.addMediaOption(media, $0) }
        }

        library.setMedia(player, media)
        library.releaseMedia(media)
        _ = library.play(player)

        self.library = library
    }

    func stopPlayback() {
        releasePlaybackResources()
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
        if let library, let player {
            library.stop(player)
            library.setMedia(player, nil)
        }

        releaseSecurityScopedURL()
        loadedURL = nil
    }

    private func releasePlaybackResources() {
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
    }

    private func releaseSecurityScopedURL() {
        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
            self.securityScopedURL = nil
        }
    }
}
