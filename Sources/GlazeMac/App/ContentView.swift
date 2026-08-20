import SwiftUI

struct ContentView: View {
    var body: some View {
        PlayerView()
            // Every surface in the app is glass over a dark backdrop, so the
            // window commits to dark regardless of the system setting — the same
            // choice IINA/Infuse/VLC make for a playback-first window.
            .preferredColorScheme(.dark)
    }
}
