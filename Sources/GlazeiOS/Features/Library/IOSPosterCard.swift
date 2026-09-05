import GlazeCore
import SwiftUI

/// One film or show, as a poster.
///
/// The 2:3 frame keeps its shape whether or not there is artwork, so a half-scraped
/// library still reads as one grid rather than two.
struct IOSPosterCard: View {
    let title: String
    let subtitle: String?
    let posterURL: URL?
    var badges: [String] = []
    var progress: Double?

    @Environment(IOSArtworkLoader.self) private var artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
            caption
        }
    }

    private var poster: some View {
        ZStack(alignment: .bottom) {
            if let image = artwork.image(for: posterURL) {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }

            if let progress, progress > 0 {
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.55))
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(IOSTheme.amber)
                            .frame(width: geometry.size.width * min(1, progress))
                    }
                }
                .frame(height: 3)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: IOSTheme.Radius.card, style: .continuous))
        .task { artwork.loadIfNeeded(posterURL) }
    }

    private var placeholder: some View {
        ZStack {
            IOSTheme.signature(for: title)
            VStack(spacing: 6) {
                Image(systemName: "film")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.35))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(8)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(IOSTheme.dim)
                        .lineLimit(1)
                }
                ForEach(badges.prefix(1), id: \.self) { badge in
                    IOSChip(text: badge, emphasized: badge == "4K")
                }
            }
        }
    }
}
