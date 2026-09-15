import CryptoKit
import Foundation
import GlazeBooks
import GlazeCore

/// Turns a book on the shelf into something the reader can page through.
///
/// Three shapes arrive here and the reader should not care which:
/// a `.cbz`/`.zip` read where it lies, a folder of images read where it lies, and a
/// `.7z` — which cannot be read in place at all. 7-Zip compresses solidly, so
/// reaching one page means decoding everything before it; it is unpacked once into
/// the caches folder and read as a folder from then on.
enum IOSComicSource {
    /// - Parameter onProgress: pages unpacked so far, and how many, while a `.7z` is
    ///   being opened for the first time. Never called for the other kinds.
    static func open(
        _ book: BookItem,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> (any ComicPages)? {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: book.url.path, isDirectory: &isDirectory)
        guard exists else { return nil }

        if isDirectory.boolValue {
            let root = book.archiveSection.map { book.url.deletingLastPathComponent().appendingPathComponent($0) }
                ?? book.url
            return try? ComicFolder(root: root)
        }

        guard BookFileTypes.isSevenZip(book.url) else {
            return try? ComicArchive.open(book.url, section: book.archiveSection)
        }

        guard let unpacked = unpack(book.url, onProgress: onProgress) else { return nil }
        let root = book.archiveSection.map { unpacked.appendingPathComponent($0) } ?? unpacked
        return try? ComicFolder(root: root)
    }

    /// Whether opening this book will cost a wait. The screen asks so it can say so
    /// before starting rather than looking frozen.
    static func needsUnpacking(_ book: BookItem) -> Bool {
        guard BookFileTypes.isSevenZip(book.url) else { return false }
        guard let directory = cacheDirectory(for: book.url) else { return false }
        return !FileManager.default.fileExists(atPath: directory.appendingPathComponent(marker).path)
    }

    // MARK: - Unpacking

    private static let marker = ".glaze-complete"

    private static func unpack(
        _ url: URL,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) -> URL? {
        guard let directory = cacheDirectory(for: url) else { return nil }
        let done = directory.appendingPathComponent(marker)

        // A marker rather than a directory check: an interrupted unpack leaves a
        // folder holding half a book, which would look finished.
        if FileManager.default.fileExists(atPath: done.path) { return directory }

        try? FileManager.default.removeItem(at: directory)
        do {
            try SevenZipArchive.extract(at: url, to: directory, onProgress: onProgress)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
        FileManager.default.createFile(atPath: done.path, contents: nil)
        return directory
    }

    /// Keyed on size as well as name, so replacing an archive with a different one
    /// under the same name does not read the old pages back.
    private static func cacheDirectory(for url: URL) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let digest = SHA256.hash(data: Data("\(url.lastPathComponent)|\(size)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return caches
            .appendingPathComponent(IOSCacheStore.Kind.archives.rawValue, isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
    }
}
