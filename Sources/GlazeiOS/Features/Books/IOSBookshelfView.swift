import GlazeBooks
import GlazeCore
import SwiftUI

/// The bookshelf: comics and PDFs kept on the device.
///
/// A phone and an iPad are the two Apple devices someone actually reads on, which is
/// why this screen exists here and not on the Mac or the television. A run of volumes
/// is one cover, the way the film library shows a series once.
struct IOSBookshelfView: View {
    let books: IOSBookLibraryModel
    let onSelectCollection: (BookCollection) -> Void

    @Environment(LibraryFavoriteStore.self) private var favorites
    @Environment(ReadingProgressStore.self) private var positions
    @State private var query = ""
    @Environment(IOSUserPreferences.self) private var preferences
    @State private var reading: BookItem?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IOSTheme.Spacing.section) {
                if books.library.isEmpty {
                    status
                } else if isSearching {
                    searchResults
                } else {
                    shelves
                }
            }
            .padding(.horizontal, IOSTheme.Spacing.medium)
            .padding(.vertical, IOSTheme.Spacing.small)
        }
        .background(IOSTheme.ground)
        .navigationTitle(L10n.string("book.shelf.title"))
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: L10n.string("book.shelf.search")
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IOSBrowseLayoutMenu(layout: layoutBinding)
            }
        }
        .onAppear { if books.phase == .idle { books.reload() } }
        .refreshable { books.reload() }
        .fullScreenCover(item: $reading) { book in
            IOSBookReaderView(book: book)
        }
    }

    // MARK: - Shelves

    @ViewBuilder
    private var shelves: some View {
        if !inProgress.isEmpty {
            bookSection(L10n.string("book.shelf.reading"), books: inProgress)
        }
        if !favoriteEntries.isEmpty {
            shelfSection(L10n.string("favorite.section"), entries: favoriteEntries)
        }
        if !books.library.collections.isEmpty {
            shelfSection(
                L10n.string("book.shelf.collections"),
                entries: books.library.collections.map(BookShelfEntry.collection)
            )
        }
        if !books.library.books.isEmpty {
            bookSection(L10n.string("book.shelf.books"), books: books.library.books)
        }
    }

    /// What was opened and not finished, most recently added first.
    private var inProgress: [BookItem] {
        books.library.allBooks.filter { positions.page(for: $0.id) != nil }
    }

    private var favoriteEntries: [BookShelfEntry] {
        let pinnedBooks = Set(favorites.itemIDs(inSource: IOSBookLibraryModel.sourceKey, kind: .book))
        let pinnedCollections = Set(favorites.itemIDs(inSource: IOSBookLibraryModel.sourceKey, kind: .bookCollection))
        return books.library.collections
            .filter { pinnedCollections.contains($0.id) }
            .map(BookShelfEntry.collection)
            + books.library.allBooks
            .filter { pinnedBooks.contains($0.id) }
            .map(BookShelfEntry.book)
    }

    private func shelfSection(_ title: String, entries: [BookShelfEntry]) -> some View {
        section(title) {
            ForEach(entries) { entry in
                switch entry {
                case .book(let book): bookCard(book)
                case .collection(let collection): collectionCard(collection)
                }
            }
        }
    }

    private func bookSection(_ title: String, books list: [BookItem]) -> some View {
        section(title) {
            ForEach(list) { book in bookCard(book) }
        }
    }

    /// One section, laid out the way the viewer asked for. The list is a stack rather
    /// than a grid — and the cards inside it are rows that never load a cover.
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.small) {
            Text(title).font(.headline)
            if preferences.browseLayout == .list {
                VStack(spacing: 0) { content() }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: IOSTheme.Spacing.large) {
                    content()
                }
            }
        }
    }

    private var columns: [GridItem] {
        let width = preferences.browseLayout == .icons ? 88.0 : 110.0
        return [GridItem(.adaptive(minimum: width, maximum: width * 1.5), spacing: IOSTheme.Spacing.medium)]
    }

    private var layoutBinding: Binding<IOSBrowseLayout> {
        Binding(get: { preferences.browseLayout }, set: { preferences.browseLayout = $0 })
    }

    private func symbol(for kind: BookItem.Kind) -> String {
        switch kind {
        case .comic: "book.pages"
        case .document: "doc.richtext"
        case .ebook: "book.closed"
        }
    }

    // MARK: - Cards

    private func bookCard(_ book: BookItem) -> some View {
        let isFavorite = favorites.contains(
            sourceKey: IOSBookLibraryModel.sourceKey,
            kind: .book,
            itemID: book.id
        )
        return Button { reading = book } label: {
            if preferences.browseLayout == .list {
                IOSBookRow(
                    title: book.displayTitle,
                    subtitle: subtitle(for: book),
                    symbol: symbol(for: book.kind),
                    progress: progress(for: book),
                    isFavorite: isFavorite
                )
            } else {
                IOSBookCoverCard(
                    title: book.displayTitle,
                    subtitle: subtitle(for: book),
                    book: book,
                    progress: progress(for: book),
                    isFavorite: isFavorite
                )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            favoriteButton(isFavorite: isFavorite, kind: .book, id: book.id, name: book.displayTitle)
            if positions.page(for: book.id) != nil {
                Button(L10n.string("book.shelf.forget"), systemImage: "arrow.counterclockwise") {
                    positions.forget(book.id)
                }
            }
        }
    }

    private func collectionCard(_ collection: BookCollection) -> some View {
        let isFavorite = favorites.contains(
            sourceKey: IOSBookLibraryModel.sourceKey,
            kind: .bookCollection,
            itemID: collection.id
        )
        let volumes = String(
            format: L10n.string("book.volume_count_format"),
            collection.volumes.count
        )
        return Button { onSelectCollection(collection) } label: {
            if preferences.browseLayout == .list {
                IOSBookRow(
                    title: collection.title,
                    subtitle: volumes,
                    symbol: "books.vertical",
                    isFavorite: isFavorite
                )
            } else {
                IOSBookCoverCard(
                    title: collection.title,
                    subtitle: volumes,
                    book: collection.volumes.first,
                    isFavorite: isFavorite
                )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            favoriteButton(
                isFavorite: isFavorite,
                kind: .bookCollection,
                id: collection.id,
                name: collection.title
            )
        }
    }

    private func favoriteButton(
        isFavorite: Bool,
        kind: LibraryFavorite.Kind,
        id: String,
        name: String
    ) -> some View {
        Button {
            favorites.toggle(
                sourceKey: IOSBookLibraryModel.sourceKey,
                kind: kind,
                itemID: id,
                name: name
            )
        } label: {
            Label(
                L10n.string(isFavorite ? "favorite.remove" : "favorite.add"),
                systemImage: isFavorite ? "star.slash" : "star"
            )
        }
    }

    // MARK: - Search

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    @ViewBuilder
    private var searchResults: some View {
        let collections = books.library.collections.filter { matches($0.title) }
        let found = books.library.allBooks.filter { matches($0.displayTitle) || matches($0.fileName) }

        if collections.isEmpty, found.isEmpty {
            Text(L10n.string("book.shelf.search.empty"))
                .font(.callout)
                .foregroundStyle(IOSTheme.dim)
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
        } else {
            if !collections.isEmpty {
                shelfSection(
                    L10n.string("book.shelf.collections"),
                    entries: collections.map(BookShelfEntry.collection)
                )
            }
            if !found.isEmpty {
                bookSection(L10n.string("book.shelf.books"), books: found)
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        text.range(
            of: query.trimmingCharacters(in: .whitespaces),
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    // MARK: - Empty

    private var status: some View {
        VStack(spacing: IOSTheme.Spacing.medium) {
            if books.isLoading {
                ProgressView()
            } else {
                Image(systemName: "books.vertical")
                    .font(.largeTitle)
                    .foregroundStyle(IOSTheme.dim)
                Text(L10n.string("book.shelf.empty.title")).font(.headline)
                Text(L10n.string("book.shelf.empty.detail"))
                    .font(.footnote)
                    .foregroundStyle(IOSTheme.dim)
                    .multilineTextAlignment(.center)
                Text(L10n.string("book.shelf.empty.formats"))
                    .font(.footnote)
                    .foregroundStyle(IOSTheme.dim)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, IOSTheme.Spacing.large)
        .padding(.top, 80)
    }

    // MARK: - Details

    /// Who wrote it, when the book says — that is what a reader scans a shelf for.
    /// Only an EPUB carries the name; a comic falls back to how long it is.
    private func subtitle(for book: BookItem) -> String? {
        if let author = book.author, !author.isEmpty { return author }
        if let pageCount = positions.pageCount(for: book.id) {
            return String(format: L10n.string("book.page_count_format"), pageCount)
        }
        switch book.kind {
        case .comic: return L10n.string("book.kind.comic")
        case .document: return L10n.string("book.kind.document")
        case .ebook: return L10n.string("book.kind.ebook")
        }
    }

    private func progress(for book: BookItem) -> Double? {
        positions.progress(for: book.id)
    }
}
