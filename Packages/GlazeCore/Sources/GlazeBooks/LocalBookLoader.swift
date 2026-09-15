import Foundation
import GlazeCore

/// Reads a folder on the device into a bookshelf.
///
/// The bookshelf's half of the same folder `LocalLibraryLoader` reads for films. Kept
/// apart from it, and in this module, because only a phone and an iPad have a
/// bookshelf — putting it in the shared package would ship a zip reader and an EPUB
/// parser to a television that will never open one.
public actor LocalBookLoader {
    public typealias Limits = LocalFolderWalker.Limits

    private let walker: LocalFolderWalker

    public init(limits: Limits = Limits(), fileManager: FileManager = .default) {
        walker = LocalFolderWalker(limits: limits, fileManager: fileManager)
    }

    /// Below this, a handful of images in a folder is artwork sitting beside
    /// something else, not a comic someone unzipped.
    private static let minimumPagesInFolder = 3

    /// - Parameter onProgress: called with folders read so far.
    public func load(
        root: URL,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> BookLibrary {
        var books: [BookItem] = []
        let scans = walker.walk(root: root, onProgress: onProgress)

        // A folder of images is a comic someone already unzipped, which is how a lot
        // of them arrive. Counted first so a run of them can be recognised as one run.
        let pagesPerFolder = Dictionary(
            uniqueKeysWithValues: scans.map { scan in
                (scan.folder.standardizedFileURL.path, scan.files.count { ComicPageMeasure.isPage($0.lastPathComponent) })
            }
        )

        for scan in scans {
            let pages = pagesPerFolder[scan.folder.standardizedFileURL.path] ?? 0
            if pages >= Self.minimumPagesInFolder, scan.folder.standardizedFileURL != root.standardizedFileURL {
                let parent = scan.folder.deletingLastPathComponent()
                // Sibling folders of pages under one parent are a run of volumes; a
                // lone one is a single book.
                let siblings = scans.filter {
                    $0.folder.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL
                        && (pagesPerFolder[$0.folder.standardizedFileURL.path] ?? 0) >= Self.minimumPagesInFolder
                }
                let isRun = siblings.count > 1 && parent.standardizedFileURL != root.standardizedFileURL
                books.append(
                    makeFolderBook(
                        folder: scan.folder,
                        root: root,
                        runFolder: isRun ? parent : nil
                    )
                )
            }

            let names = scan.fileNames
            for file in scan.files {
                guard let kind = BookFileTypes.kind(of: file) else { continue }

                // A `.zip` or `.7z` is a container for anything. Asking it costs a
                // read of the archive's index, whatever the archive weighs.
                let isSevenZip = BookFileTypes.isSevenZip(file)
                if BookFileTypes.needsInspection(file) {
                    let holdsPages = isSevenZip
                        ? SevenZipArchive.holdsPages(at: file)
                        : ComicArchive.holdsPages(file)
                    guard holdsPages else { continue }
                }

                // One archive routinely holds a whole run — a folder per volume.
                // Read as a single book that is thousands of pages with no breaks.
                let sections = kind == .comic
                    ? (isSevenZip ? SevenZipArchive.volumes(at: file) : ComicArchive.volumes(in: file))
                    : []
                if sections.isEmpty {
                    books.append(
                        makeBook(file: file, kind: kind, siblings: names, folder: scan.folder, root: root)
                    )
                } else {
                    for section in sections {
                        books.append(
                            makeBook(
                                file: file,
                                kind: kind,
                                siblings: names,
                                folder: scan.folder,
                                root: root,
                                section: section
                            )
                        )
                    }
                }
            }
        }
        return BookLibraryIndex.build(from: books)
    }

    /// A folder of images, as a book. Its own name is what it is called; when it sits
    /// among sibling folders of pages, the parent names the run they belong to.
    private func makeFolderBook(folder: URL, root: URL, runFolder: URL?) -> BookItem {
        let parsed = BookTitleParser.parse(fileName: folder.lastPathComponent, kind: .comic)
        let values = try? folder.resourceValues(forKeys: [.contentModificationDateKey])
        let runTitle = runFolder.map {
            BookTitleParser.parse(fileName: $0.lastPathComponent, kind: .comic).title
        }

        return BookItem(
            id: LocalFolderWalker.identifier(for: folder, root: root),
            kind: .comic,
            fileName: folder.lastPathComponent,
            url: folder,
            archiveSection: runFolder != nil ? folder.lastPathComponent : nil,
            collectionKey: runFolder.map { LocalFolderWalker.identifier(for: $0, root: root) },
            title: runTitle?.isEmpty == false
                ? runTitle!
                : (parsed.title.isEmpty ? folder.lastPathComponent : parsed.title),
            volume: parsed.volume,
            volumeUnit: parsed.unit,
            dateAdded: values?.contentModificationDate
        )
    }

    /// A cover is found the same way a film's poster is: a file beside it that carries
    /// its name. Nothing is drawn out of the book itself here — opening a 400MB PDF to
    /// make one thumbnail is the shelf's job, on demand, not the scan's.
    private func makeBook(
        file: URL,
        kind: BookItem.Kind,
        siblings: [String],
        folder: URL,
        root: URL,
        section: String? = nil
    ) -> BookItem {
        let companions = MediaCompanionFinder.find(
            videoName: file.lastPathComponent,
            among: siblings
        )
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        // A book knows its own name. `dawkins_gene.epub` is what the file is called;
        // `이기적 유전자` is what it is, and that is what belongs on a shelf. Reading
        // it costs a few kilobytes whatever the book weighs.
        let package = kind == .ebook ? try? EPUBBook.readPackage(at: file) : nil
        let named = package?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        // A volume inside a run is named by its own folder — `01권` — while the
        // archive's name is what the run is called.
        let source = section ?? (named?.isEmpty == false ? named! : file.lastPathComponent)
        let parsed = BookTitleParser.parse(fileName: source, kind: kind)
        let runTitle = BookTitleParser.parse(fileName: file.lastPathComponent, kind: kind).title

        let identifier = LocalFolderWalker.identifier(for: file, root: root)
        return BookItem(
            id: section.map { "\(identifier)#\($0)" } ?? identifier,
            kind: kind,
            fileName: file.lastPathComponent,
            url: file,
            archiveSection: section,
            collectionKey: section != nil ? identifier : nil,
            // A volume inside an archive belongs to the run the archive is named for.
            // A loose file called `01권.cbz` inside `원피스/` is named by its folder,
            // which is how people organise a run on disk.
            title: section != nil
                ? (runTitle.isEmpty ? file.lastPathComponent : runTitle)
                : (parsed.title.isEmpty ? folder.lastPathComponent : parsed.title),
            author: package?.author,
            volume: parsed.volume,
            volumeUnit: parsed.unit,
            coverURL: companions.poster.map(folder.appendingPathComponent),
            byteCount: values?.fileSize.map(Int64.init),
            dateAdded: values?.contentModificationDate
        )
    }
}
