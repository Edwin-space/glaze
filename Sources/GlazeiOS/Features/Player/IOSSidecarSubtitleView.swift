import GlazeCore
import SwiftUI

/// Cached SRT text stays in the video rectangle, not in the transport bar. Native
/// embedded/ASS subtitles continue to use VLC's renderer and cannot double up here.
struct IOSSidecarSubtitleView: View {
    let text: String
    let videoSize: CGSize?
    let fillsScreen: Bool
    let scale: Float

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.size
            let rect = videoRect(in: bounds)
            VStack {
                Spacer(minLength: 0)
                Text(text)
                    .font(.system(size: min(max(rect.width / 28, 17), 28)
                        * CGFloat(SubtitleScale.fraction(fromPercent: scale)), weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                    .shadow(color: .black, radius: 1)
                    .padding(.horizontal, IOSTheme.Spacing.large)
                    .padding(.bottom, max(16, rect.height * 0.06))
                    .accessibilityIdentifier("player.sidecar.caption")
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
    }

    private func videoRect(in bounds: CGSize) -> CGRect {
        guard !fillsScreen, let videoSize, videoSize.width > 0, videoSize.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let factor = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * factor, height: videoSize.height * factor)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
