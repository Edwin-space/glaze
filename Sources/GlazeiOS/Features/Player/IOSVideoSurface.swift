import SwiftUI
import UIKit
import VLCKit

/// The view VLC draws into.
struct IOSVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if player.drawable == nil { player.drawable = uiView }
    }
}
