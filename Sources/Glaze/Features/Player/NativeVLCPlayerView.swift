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
    private var instance: NativeVLCLibrary.InstanceHandle?
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

        stopPlayback()
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

        guard let instance = library.makeInstance() else {
            loadedURL = nil
            releasePlaybackResources()
            onFailure?("Unable to create libVLC instance")
            assertionFailure("Unable to create libVLC instance")
            return
        }

        guard let media = url.path.withCString({ library.newMediaPath(instance, $0) }) else {
            loadedURL = nil
            library.releaseInstance(instance)
            releasePlaybackResources()
            onFailure?("Unable to create libVLC media")
            assertionFailure("Unable to create libVLC media")
            return
        }

        guard let player = library.newPlayerFromMedia(media) else {
            loadedURL = nil
            library.releaseMedia(media)
            library.releaseInstance(instance)
            releasePlaybackResources()
            onFailure?("Unable to create libVLC media player")
            assertionFailure("Unable to create libVLC media player")
            return
        }

        library.releaseMedia(media)
        library.setNSObject(player, Unmanaged.passUnretained(self).toOpaque())
        _ = library.play(player)

        self.library = library
        self.instance = instance
        self.player = player
    }

    func stopPlayback() {
        releasePlaybackResources()
    }

    private func releasePlaybackResources() {
        if let library {
            if let player {
                library.stop(player)
                library.releasePlayer(player)
                self.player = nil
            }

            if let instance {
                library.releaseInstance(instance)
                self.instance = nil
            }
        }

        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
            self.securityScopedURL = nil
        }

        loadedURL = nil
        self.library = nil
    }
}
