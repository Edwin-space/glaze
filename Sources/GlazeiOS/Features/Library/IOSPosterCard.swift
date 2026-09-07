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
    /// A grid needs the title under the poster. A detail screen already has the
    /// title beside it, and repeating it there reads as a mistake.
    var showsCaption = true

    @Environment(IOSArtworkLoader.self) private var artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
            if showsCaption { caption }
        }
    }

    /// The frame is set by an empty rectangle, not by the artwork.
    ///
    /// A resizable image told to fill has no size of its own and was taking the
    /// container with it: posters came out square instead of 2:3, and on the detail
    /// screen the artwork ran off the side of the display. Laying the image over a
    /// shape that already has the right shape, and clipping, pins it down.
    private var poster: some View {
        Rectangle()
            .fill(Color.clear)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image = artwork.image(for: posterURL) {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .overlay(alignment: .bottom) {
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
