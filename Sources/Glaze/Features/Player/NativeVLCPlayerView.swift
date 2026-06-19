import AppKit
import SwiftUI

struct NativeVLCSurfaceView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NativeVLCPlayerView {
        let view = NativeVLCPlayerView()
        view.load(url)
        return view
    }

    func updateNSView(_ view: NativeVLCPlayerView, context: Context) {
        view.load(url)
    }

    static func dismantleNSView(_ nsView: NativeVLCPlayerView, coordinator: ()) {
        nsView.stopPlayback()
    }
}

final class NativeVLCPlayerView: NSView {
    private var instance: NativeVLCLibrary.InstanceHandle?
    private var player: NativeVLCLibrary.MediaPlayerHandle?
    private var loadedURL: URL?

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

        let library = NativeVLCLibrary.shared
        guard let instance = library.makeInstance() else {
            assertionFailure("Unable to create libVLC instance")
            return
        }

        guard let media = url.path.withCString({ library.newMediaPath(instance, $0) }) else {
            library.releaseInstance(instance)
            assertionFailure("Unable to create libVLC media")
            return
        }

        guard let player = library.newPlayerFromMedia(media) else {
            library.releaseMedia(media)
            library.releaseInstance(instance)
            assertionFailure("Unable to create libVLC media player")
            return
        }

        library.releaseMedia(media)
        library.setNSObject(player, Unmanaged.passUnretained(self).toOpaque())
        _ = library.play(player)

        self.instance = instance
        self.player = player
    }

    func stopPlayback() {
        releasePlaybackResources()
    }

    private func releasePlaybackResources() {
        let library = NativeVLCLibrary.shared

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
}
