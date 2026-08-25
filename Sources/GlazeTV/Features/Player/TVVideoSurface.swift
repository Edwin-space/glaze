import SwiftUI
import UIKit
import VLCKit

/// The view VLC draws video into.
///
/// VLCKit renders into a plain UIView it owns the layer of, so this is a thin bridge
/// and deliberately does nothing else — no controls, no gestures. Everything the viewer
/// interacts with sits above it in SwiftUI, where focus and the remote are handled.
struct TVVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
