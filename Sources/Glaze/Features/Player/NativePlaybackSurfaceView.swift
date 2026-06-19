import SwiftUI

struct NativePlaybackSurfaceView: View {
    var body: some View {
        VStack(spacing: GlazeSpacing.md) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: GlazeSpacing.xs) {
                Text(L10n.string("player.native_engine.title"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(L10n.string("player.native_engine.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(GlazeSpacing.xl)
    }
}
