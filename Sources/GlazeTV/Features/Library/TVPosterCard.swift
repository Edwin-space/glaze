import GlazeCore
import SwiftUI

/// One film or show on a shelf, as a poster.
///
/// The 2:3 portrait frame is what Apple's TV app uses and what people recognise a
/// library by. When there is no poster — a DLNA server, or a film the Mac has not
/// looked up yet — the frame keeps its shape and fills with the title's own colour
/// rather than collapsing to a different layout, so a half-scraped library still reads
/// as one shelf.
struct TVPosterCard: View {
    let title: String
    let subtitle: String?
    let posterURL: URL?
    var badges: [String] = []
    var progress: Double?
    var width: CGFloat = 220

    @Environment(TVArtworkLoader.self) private var artwork
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            poster
            caption
        }
        .frame(width: width)
    }

    private var poster: some View {
        ZStack(alignment: .bottom) {
            if let image = artwork.image(for: posterURL) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }

            if let progress, progress > 0 {
                progressBar(progress)
            }
        }
        .frame(width: width, height: width * 3 / 2)
        .clipShape(RoundedRectangle(cornerRadius: TVTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TVTheme.Radius.card, style: .continuous)
                .strokeBorder(TVTheme.amber, lineWidth: isFocused ? 4 : 0)
        )
        .shadow(color: .black.opacity(isFocused ? 0.65 : 0.3), radius: isFocused ? 28 : 12, y: isFocused ? 16 : 8)
        .scaleEffect(isFocused ? 1.08 : 1)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .onAppear { artwork.loadIfNeeded(posterURL) }
    }

    private var placeholder: some View {
        ZStack {
            TVTheme.signature(for: title)
            VStack(spacing: 10) {
                Image(systemName: "film")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(18)
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.55))
            GeometryReader { geometry in
                Rectangle()
                    .fill(TVTheme.amber)
                    .frame(width: geometry.size.width * min(1, progress))
            }
        }
        .frame(height: 6)
    }

    /// The title is drawn twice only when there is nothing else in the frame: with a
    /// poster it belongs under the picture, without one it is already the picture.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            if artwork.image(for: posterURL) != nil {
                Text(title)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.88))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 19))
                        .foregroundStyle(TVTheme.dim)
                        .lineLimit(1)
                }
                ForEach(badges.prefix(1), id: \.self) { badge in
                    TVChip(text: badge, emphasized: badge == "4K")
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
