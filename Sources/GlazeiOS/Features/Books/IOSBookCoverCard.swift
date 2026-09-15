import GlazeBooks
import GlazeCore
import SwiftUI

/// One book on the shelf.
///
/// The frame is fixed at 2:3 and the artwork is laid over it, the same arrangement
/// the film posters use — a shelf where every cover is the shape of whatever scan it
/// came from does not read as a shelf.
struct IOSBookCoverCard: View {
    let title: String
    let subtitle: String?
    let book: BookItem?
    var progress: Double?
    var isFavorite = false

    @Environment(IOSBookCoverLoader.self) private var covers

    var body: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.tight) {
            cover
            caption
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var spokenLabel: String {
        var parts = [title]
        if let subtitle { parts.append(subtitle) }
        if isFavorite { parts.append(L10n.string("favorite.section")) }
        if let progress, progress > 0 {
            parts.append(String(format: L10n.string("book.a11y.read_format"), Int(progress * 100)))
        }
        return parts.joined(separator: ", ")
    }

    private var cover: some View {
        Rectangle()
            .fill(Color.clear)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let book, let image = covers.image(for: book) {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(IOSTheme.amber)
                        .padding(IOSTheme.Spacing.tight)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(IOSTheme.Spacing.tight)
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
            .task { if let book { covers.loadIfNeeded(book) } }
    }

    private var placeholder: some View {
        ZStack {
            IOSTheme.signature(for: title)
            // No title here: the caption beneath already says it, and printing it
            // twice is what a book with no artwork used to look like.
            Image(systemName: book?.kind == .comic ? "book.pages" : "doc.richtext")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.hair) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(IOSTheme.dim)
                    .lineLimit(1)
            }
        }
    }
}
