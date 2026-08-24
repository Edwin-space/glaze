import GlazeCore
import SwiftUI

/// Placeholder while the Apple TV app is built out. It exists first to prove the shared
/// core compiles for tvOS, which is the thing that decides the shape of everything else.
struct TVRootView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text(L10n.string("app.name"))
                .font(.system(size: 76, weight: .bold))
            Text(verbatim: "GlazeCore \(SubtitleCue(startTime: 0, endTime: 1, text: "ok").text)")
                .foregroundStyle(.secondary)
        }
    }
}
