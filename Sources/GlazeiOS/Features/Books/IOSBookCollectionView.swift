import GlazeBooks
import GlazeCore
import SwiftUI

/// One run of volumes.
///
/// The equivalent of the series screen on the film side, and kept as plain as that
/// one: what is here is a list of volumes, in order, with how far through each one
/// the viewer got.
struct IOSBookCollectionView: View {
    let collection: BookCollection

    @Environment(LibraryFavoriteStore.self) private var favorites
    @Environment(ReadingProgressStore.self) private var positions
    @Environment(IOSUserPreferences.self) private var preferences
    @State private var reading: BookItem?

    var body: some View {
        ScrollView {
            // The screen where the choice matters most: a run can be seventy volumes,
            // and every cover is an archive opened and an image decoded.
            layout {
                ForEach(collection.volumes) { volume in
                    Button { reading = volume } label: {
                        if preferences.browseLayout == .list {
                            IOSBookRow(
                                title: volume.volumeRowTitle,
                                subtitle: subtitle(for: volume),
                                symbol: "book.pages",
                                progress: progress(for: volume),
                                isFavorite: isFavorite(volume)
                            )
                        } else {
                            IOSBookCoverCard(
                                title: volume.volumeRowTitle,
                                subtitle: subtitle(for: volume),
                                book: volume,
                                progress: progress(for: volume),
                                isFavorite: isFavorite(volume)
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            favorites.toggle(
                                sourceKey: IOSBookLibraryModel.sourceKey,
                                kind: .book,
                                itemID: volume.id,
                                name: volume.displayTitle
                            )
                        } label: {
                            Label(
                                L10n.string(isFavorite(volume) ? "favorite.remove" : "favorite.add"),
                                systemImage: isFavorite(volume) ? "star.slash" : "star"
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, IOSTheme.Spacing.medium)
            .padding(.vertical, IOSTheme.Spacing.small)
        }
        .background(IOSTheme.ground)
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IOSBrowseLayoutMenu(
                    layout: Binding(
                        get: { preferences.browseLayout },
                        set: { preferences.browseLayout = $0 }
                    )
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(
                        sourceKey: IOSBookLibraryModel.sourceKey,
                        kind: .bookCollection,
                        itemID: collection.id,
                        name: collection.title
                    )
                } label: {
                    Image(systemName: isCollectionFavorite ? "star.fill" : "star")
                }
                .tint(IOSTheme.amber)
                .accessibilityLabel(L10n.string(isCollectionFavorite ? "favorite.remove" : "favorite.add"))
            }
        }
        .fullScreenCover(item: $reading) { volume in
            IOSBookReaderView(book: volume)
        }
    }

    private var isCollectionFavorite: Bool {
        favorites.contains(
            sourceKey: IOSBookLibraryModel.sourceKey,
            kind: .bookCollection,
            itemID: collection.id
        )
    }

    private func isFavorite(_ volume: BookItem) -> Bool {
        favorites.contains(sourceKey: IOSBookLibraryModel.sourceKey, kind: .book, itemID: volume.id)
    }

    /// A stack for the list, a grid for the two picture layouts.
    @ViewBuilder
    private func layout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if preferences.browseLayout == .list {
            LazyVStack(spacing: 0) { content() }
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: IOSTheme.Spacing.large) {
                content()
            }
        }
    }

    private var columns: [GridItem] {
        let width = preferences.browseLayout == .icons ? 88.0 : 110.0
        return [GridItem(.adaptive(minimum: width, maximum: width * 1.5), spacing: IOSTheme.Spacing.medium)]
    }

    private func subtitle(for volume: BookItem) -> String? {
        guard let pageCount = positions.pageCount(for: volume.id) else { return nil }
        return String(format: L10n.string("book.page_count_format"), pageCount)
    }

    private func progress(for volume: BookItem) -> Double? {
        positions.progress(for: volume.id)
    }
}
