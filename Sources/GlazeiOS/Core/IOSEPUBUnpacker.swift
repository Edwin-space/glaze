import CryptoKit
import Foundation
import GlazeBooks
import GlazeCore

/// A book unpacked onto disk, ready for a web view to read.
struct IOSOpenedEPUB: Sendable {
    let root: URL
    /// Chapter paths relative to `root`, in reading order.
    let spine: [String]
    let chapters: [EPUBChapter]
    let title: String?
    let author: String?
}

/// Unpacks a book into the caches folder, once.
///
/// A web view resolves a chapter's stylesheets, fonts and images against the
/// document's own folder, so the book has to exist as folders and files somewhere.
/// The caches folder is the right somewhere: the system may clear it, and if it does
/// the next open simply unpacks again.
enum IOSEPUBUnpacker {
    static func open(_ url: URL, identifier: String) -> IOSOpenedEPUB? {
        guard let book = try? EPUBBook.open(url) else { return nil }
        guard let root = directory(for: identifier, url: url) else { return nil }

        // A marker rather than a directory check: an interrupted unpack leaves a
        // folder full of half a book, which would look finished.
        let marker = root.appendingPathComponent(".glaze-complete")
        if !FileManager.default.fileExists(atPath: marker.path) {
            try? FileManager.default.removeItem(at: root)
            guard (try? book.extract(to: root)) != nil else { return nil }
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        }

        return IOSOpenedEPUB(
            root: root,
            spine: book.package.spine,
            chapters: book.package.chapters,
            title: book.package.title,
            author: book.package.author
        )
    }

    /// Keyed on the file's size as well as its name, so replacing a book with a
    /// different edition under the same name does not read the old one back.
    private static func directory(for identifier: String, url: URL) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let digest = SHA256.hash(data: Data("\(identifier)|\(size)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return caches
            .appendingPathComponent(IOSCacheStore.Kind.books.rawValue, isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
    }
}
