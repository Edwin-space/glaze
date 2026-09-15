import Foundation
import GlazeCore

/// What Glaze can open as a book.
///
/// `.cbr` is deliberately absent, and stays absent (`docs/33`): it is a RAR archive,
/// and every RAR decoder available carries licence terms this project will not take
/// on. Listing a file the reader cannot turn a page of would be worse than not
/// listing it.
public enum BookFileTypes {
    /// One image per page, in a zip. `.cbz` says so by its name; a plain `.zip` has
    /// to be opened and asked, because a zip is a container for anything.
    public static let comic: Set<String> = ["cbz", "zip", "7z", "cb7"]
    /// These hold anything at all, so the archive has to be opened and asked.
    public static let ambiguous: Set<String> = ["zip", "7z"]
    /// Solidly compressed, so pages cannot be read one at a time — these are unpacked
    /// once and read from disk after that.
    public static let sevenZip: Set<String> = ["7z", "cb7"]

    public static func isSevenZip(_ url: URL) -> Bool {
        sevenZip.contains(url.pathExtension.lowercased())
    }
    public static let document: Set<String> = ["pdf"]
    /// Reflowable text — the standard ebook.
    public static let ebook: Set<String> = ["epub"]

    /// Every extension the shelf will take — used to decide whether a file listed on
    /// a server is something this device can read.
    public static var all: Set<String> { comic.union(document).union(ebook) }

    /// Whether the file's name alone settles what it is, or the archive has to be
    /// opened to find out.
    public static func needsInspection(_ url: URL) -> Bool {
        ambiguous.contains(url.pathExtension.lowercased())
    }

    public static func kind(of url: URL) -> BookItem.Kind? {
        let suffix = url.pathExtension.lowercased()
        if comic.contains(suffix) { return .comic }
        if document.contains(suffix) { return .document }
        if ebook.contains(suffix) { return .ebook }
        return nil
    }

    public static func isBook(_ url: URL) -> Bool { kind(of: url) != nil }
}

/// One book, comic volume, or PDF.
///
/// The film side of the library resolves everything up front because a television
/// redraws a shelf on every focus change; a bookshelf is scrolled rather than
/// focused, but the parsing cost is the same and so is the answer.
public struct BookItem: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case comic
        case document
        case ebook
    }

    public let id: String
    public let kind: Kind
    /// What the file is called, kept for the info line.
    public let fileName: String
    public let url: URL
    /// The folder inside the archive this volume lives in, when one archive holds a
    /// whole run. Nil when the file is one book.
    public let archiveSection: String?
    /// What binds this to the others it came with. Everything out of one archive
    /// belongs together whether or not its folders happen to be numbered — otherwise
    /// a shelf of downloads is hundreds of loose covers to scroll past.
    public let collectionKey: String?
    /// The name without the volume number — what the collection is called.
    public let title: String
    /// Only an EPUB says who wrote it; a comic's file name rarely does.
    public let author: String?
    public let volume: Int?
    /// What the file name called the volume — `권`, `화`, `집`. Nil when the number
    /// came from `Vol.` or a bare digit.
    public let volumeUnit: String?
    public let coverURL: URL?
    public let byteCount: Int64?
    public let dateAdded: Date?

    public init(
        id: String,
        kind: Kind,
        fileName: String,
        url: URL,
        archiveSection: String? = nil,
        collectionKey: String? = nil,
        title: String,
        author: String? = nil,
        volume: Int? = nil,
        volumeUnit: String? = nil,
        coverURL: URL? = nil,
        byteCount: Int64? = nil,
        dateAdded: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.url = url
        self.archiveSection = archiveSection
        self.collectionKey = collectionKey
        self.title = title
        self.author = author
        self.volume = volume
        self.volumeUnit = volumeUnit
        self.coverURL = coverURL
        self.byteCount = byteCount
        self.dateAdded = dateAdded
    }

    /// `3권` in Korean, `Vol. 3` in English — the shelf shows this under the cover.
    ///
    /// A file that said `화` gets `화` back. Calling episode three "3권" is simply
    /// wrong, and webtoons are numbered by episode.
    public var volumeLabel: String? {
        guard let volume else { return nil }
        if let volumeUnit { return "\(volume)\(volumeUnit)" }
        return String(format: L10n.string("book.volume_format"), volume)
    }

    /// What to call this volume inside its own run.
    ///
    /// The number when the name carries one. When it does not — a download whose inner
    /// archives are named in a way the parser cannot read — the section's own filename
    /// is what tells one volume from another. Falling through to the run's title made
    /// every row on the collection screen say the same thing.
    public var volumeRowTitle: String {
        if let volumeLabel { return volumeLabel }
        if let archiveSection, !archiveSection.isEmpty {
            let name = (archiveSection as NSString).lastPathComponent
            let stem = (name as NSString).deletingPathExtension
            if !stem.isEmpty { return stem }
        }
        return displayTitle
    }

    /// The full name, for a screen that shows one book rather than a row of them.
    public var displayTitle: String {
        guard let volumeLabel else { return title }
        return "\(title) \(volumeLabel)"
    }
}

/// A run of volumes under one name — the bookshelf's answer to a series.
public struct BookCollection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Lowest volume first.
    public let volumes: [BookItem]

    public var coverURL: URL? { volumes.first(where: { $0.coverURL != nil })?.coverURL }
    public var dateAdded: Date? { volumes.compactMap(\.dateAdded).max() }

    public init(id: String, title: String, volumes: [BookItem]) {
        self.id = id
        self.title = title
        self.volumes = volumes
    }
}

/// A book, or a run of volumes — what a shelf holds when it can hold either.
public enum BookShelfEntry: Identifiable, Equatable, Sendable {
    case book(BookItem)
    case collection(BookCollection)

    public var id: String {
        switch self {
        case .book(let book): "book:\(book.id)"
        case .collection(let collection): "collection:\(collection.id)"
        }
    }

    public var title: String {
        switch self {
        case .book(let book): book.displayTitle
        case .collection(let collection): collection.title
        }
    }

    public var coverURL: URL? {
        switch self {
        case .book(let book): book.coverURL
        case .collection(let collection): collection.coverURL
        }
    }

    public var dateAdded: Date? {
        switch self {
        case .book(let book): book.dateAdded
        case .collection(let collection): collection.dateAdded
        }
    }
}

/// A folder of books, understood.
public struct BookLibrary: Equatable, Sendable {
    /// Books that stand on their own — a novel, a manual, a one-shot.
    public let books: [BookItem]
    public let collections: [BookCollection]
    /// Newest first. A collection appears once, dated by its newest volume.
    public let recentlyAdded: [BookShelfEntry]

    public var isEmpty: Bool { books.isEmpty && collections.isEmpty }
    public var allBooks: [BookItem] { books + collections.flatMap(\.volumes) }

    public init(
        books: [BookItem] = [],
        collections: [BookCollection] = [],
        recentlyAdded: [BookShelfEntry] = []
    ) {
        self.books = books
        self.collections = collections
        self.recentlyAdded = recentlyAdded
    }
}
