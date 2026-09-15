import GlazeBooks
import GlazeCore
import SwiftUI

/// A book as one line of text.
///
/// The point of this row is what it does **not** do: it never asks for a cover. Every
/// thumbnail on the shelf means opening an archive and decoding an image, and for a
/// run of seventy volumes that is seventy of them before the screen settles. Someone
/// who has hundreds of books and knows what they are called should be able to say
/// "just the names" and pay nothing.
struct IOSBookRow: View {
    let title: String
    let subtitle: String?
    let symbol: String
    var progress: Double?
    var isFavorite = false

    var body: some View {
        HStack(spacing: IOSTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(IOSTheme.amber)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: IOSTheme.Spacing.hair) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: IOSTheme.Spacing.tight) {
                    if let subtitle { Text(subtitle) }
                    if let progress, progress > 0 {
                        Text(String(format: L10n.string("book.shelf.progress_format"), Int(progress * 100)))
                    }
                }
                .font(.caption)
                .foregroundStyle(IOSTheme.dim)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(IOSTheme.amber)
            }
        }
        .padding(.vertical, IOSTheme.Spacing.small)
        .contentShape(Rectangle())
    }
}
