import GlazeCore
import SwiftUI

/// One film on a shelf.
///
/// A 16:9 tile rather than the 2:3 poster Plex uses, because there is no poster to put
/// in it. A portrait frame with no art in it reads as a missing image; a landscape one
/// reads as a video, which is what it is.
struct TVMediaCard: View {
    let item: PlayableItem
    let progress: Double?

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tile
            caption
        }
        .frame(width: 420)
    }

    private var tile: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: TVTheme.Radius.card, style: .continuous)
                .fill(TVTheme.signature(for: item.title))

            // Keeps the title legible over the lighter end of the gradient.
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: TVTheme.Radius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Text(item.parsed.title)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let progress, progress > 0 {
                    resumeBar(progress)
                }
            }
            .padding(18)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: TVTheme.Radius.card, style: .continuous)
                .strokeBorder(TVTheme.amber, lineWidth: isFocused ? 4 : 0)
        )
        .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 26, y: 14)
        .scaleEffect(isFocused ? 1.06 : 1)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }

    /// How far in the viewer got. The one piece of state that makes a library feel like
    /// it remembers you.
    private func resumeBar(_ progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(TVTheme.amber)
                    .frame(width: geometry.size.width * min(1, progress))
            }
        }
        .frame(height: 5)
    }

    private var caption: some View {
        HStack(spacing: 8) {
            if let year = item.parsed.year {
                Text(String(year))
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(TVTheme.dim)
            }

            ForEach(item.parsed.badges.prefix(2), id: \.self) { badge in
                TVChip(text: badge, emphasized: badge == "4K")
            }

            Spacer(minLength: 0)
        }
        .opacity(isFocused ? 1 : 0.75)
    }
}
