import CryptoKit
import Foundation
import GlazeBooks
import GlazeCore
import PDFKit
import SwiftUI
import UIKit

/// Draws the cover of a book, whatever it takes to get one.
///
/// Three cases, in order of cost: an image sitting beside the file, the first page of
/// a comic archive, or page one of a PDF. The last two mean opening the book, which
/// is why the result is written to the caches folder — a shelf of forty comics would
/// otherwise unzip forty archives on every launch.
@Observable
@MainActor
final class IOSBookCoverLoader {
    private var images: [String: Image] = [:]
    private var failed: Set<String> = []
    private var inFlight: Set<String> = []

    /// Wide enough for a cover on the largest iPad at 3×, and no wider.
    nonisolated private static let maximumPixels = 700

    func image(for book: BookItem) -> Image? { images[book.id] }

    func loadIfNeeded(_ book: BookItem) {
        guard images[book.id] == nil, !failed.contains(book.id), !inFlight.contains(book.id) else { return }
        inFlight.insert(book.id)

        Task { [weak self] in
            let rendered = await Task.detached(priority: .utility) { () -> UIImage? in
                Self.render(book)
            }.value

            guard let self else { return }
            inFlight.remove(book.id)
            if let rendered {
                images[book.id] = Image(uiImage: rendered)
            } else {
                failed.insert(book.id)
            }
        }
    }

    // MARK: - Off the main actor

    nonisolated private static func render(_ book: BookItem) -> UIImage? {
        if let cached = cachedImage(for: book) { return cached }

        let drawn: UIImage? = switch book.kind {
        case .comic: comicCover(book)
        case .document: documentCover(book)
        case .ebook: ebookCover(book)
        }

        guard let drawn else { return nil }
        writeCache(drawn, for: book)
        return drawn
    }

    nonisolated private static func comicCover(_ book: BookItem) -> UIImage? {
        if let sidecar = book.coverURL, let data = try? Data(contentsOf: sidecar) {
            return thumbnail(from: data)
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: book.url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            let root = book.archiveSection
                .map { book.url.deletingLastPathComponent().appendingPathComponent($0) } ?? book.url
            guard let first = ComicFolder.pages(in: root).first,
                  let data = try? Data(contentsOf: first, options: .mappedIfSafe) else { return nil }
            return thumbnail(from: data)
        }

        // Not for a `.7z`: solid compression means the only way to the first page is
        // to unpack the whole archive, and a shelf full of them would unpack the lot
        // to draw thumbnails. The cover appears once the book has been opened.
        guard !BookFileTypes.isSevenZip(book.url) else { return nil }

        guard let data = ComicArchive.coverData(of: book.url, section: book.archiveSection) else {
            return nil
        }
        return thumbnail(from: data)
    }

    /// An EPUB names its cover in the package document rather than putting it first,
    /// so this asks the book rather than guessing at the archive's first image.
    nonisolated private static func ebookCover(_ book: BookItem) -> UIImage? {
        if let sidecar = book.coverURL, let data = try? Data(contentsOf: sidecar) {
            return thumbnail(from: data)
        }
        guard let opened = try? EPUBBook.open(book.url),
              let path = opened.package.coverPath,
              let data = try? opened.archive.data(named: path) else { return nil }
        return thumbnail(from: data)
    }

    nonisolated private static func documentCover(_ book: BookItem) -> UIImage? {
        if let sidecar = book.coverURL, let data = try? Data(contentsOf: sidecar) {
            return thumbnail(from: data)
        }
        guard let document = PDFDocument(url: book.url), let page = document.page(at: 0) else { return nil }
        let box = page.bounds(for: .cropBox)
        guard box.height > 0 else { return nil }
        let scale = CGFloat(maximumPixels) / max(box.width, box.height)
        return page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .cropBox)
    }

    /// Decoded straight to the size it will be drawn at. A scan is often 3000px tall,
    /// and forty of those held full size is how a shelf runs a phone out of memory.
    nonisolated private static func thumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: - The caches folder

    nonisolated private static func cachedImage(for book: BookItem) -> UIImage? {
        guard let url = cacheURL(for: book),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    nonisolated private static func writeCache(_ image: UIImage, for book: BookItem) {
        guard let url = cacheURL(for: book), let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    /// Keyed on the file's size as well as its path, so replacing a volume with a
    /// better scan under the same name does not keep showing the old cover.
    nonisolated private static func cacheURL(for book: BookItem) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let seed = "\(book.id)|\(book.byteCount ?? 0)"
        let digest = SHA256.hash(data: Data(seed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return caches
            .appendingPathComponent(IOSCacheStore.Kind.covers.rawValue, isDirectory: true)
            .appendingPathComponent("\(digest).jpg")
    }
}
