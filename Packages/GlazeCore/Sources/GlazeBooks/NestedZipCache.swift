import CryptoKit
import Foundation

/// A zip inside a zip, made readable.
///
/// The commonest shape a Korean manga scan arrives in is not a `.cbz` of images: it is
/// one `.zip` holding **one `.zip` per volume**, sometimes with a `[Cover].jpg` beside
/// them. Sixteen of the seventeen archives on the phone this was written for are built
/// that way, and every one of them was invisible — the shelf asked "does this archive
/// hold any images?", the answer was no, and the book was dropped.
///
/// The inner archives are deflated, so they cannot be read where they lie: a zip's
/// central directory has to be seekable. Each one is inflated to the caches folder
/// once and then read as an ordinary archive, which is the same bargain the `.7z`
/// path already makes and for the same reason.
public enum NestedZipCache {
    /// Where unpacked archives live, named here because this module is the one that
    /// writes them. The app's cache screen reports and clears the same folder.
    public static let cacheFolderName = "glaze-archives"

    /// Extensions that make an entry an archive of its own rather than a page.
    static let archiveExtensions: Set<String> = ["zip", "cbz"]

    static func isArchive(_ name: String) -> Bool {
        guard !name.hasSuffix("/"), !name.contains("__MACOSX") else { return false }
        let file = (name as NSString).lastPathComponent
        guard !file.hasPrefix(".") else { return false }
        return archiveExtensions.contains((file as NSString).pathExtension.lowercased())
    }

    /// The inner archive as a file on disk, extracting it if this is the first ask.
    ///
    /// - Returns: nil when the member cannot be read; the caller treats that as a
    ///   volume that is not there rather than a broken book.
    static func file(forEntry name: String, in outer: URL) -> URL? {
        guard let destination = location(forEntry: name, in: outer) else { return nil }
        let fileManager = FileManager.default

        // A part-written file would parse as a damaged archive, so the finished one is
        // moved into place under its real name only once it is whole.
        if fileManager.fileExists(atPath: destination.path) { return destination }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let archive = try ZipArchive.open(outer)
            let data = try archive.data(named: name)

            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString).part")
            try data.write(to: staging, options: .atomic)
            try fileManager.moveItem(at: staging, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// The unpacked inner archive, only if it is already there. Never does the work.
    static func existingFile(forEntry name: String, in outer: URL) -> URL? {
        guard let destination = location(forEntry: name, in: outer),
              FileManager.default.fileExists(atPath: destination.path)
        else { return nil }
        return destination
    }

    /// The inner archive's first page, read from the front of it.
    ///
    /// Costs a few megabytes of inflating rather than the whole volume, and writes
    /// nothing. Returns nil when the first page sits further in than the prefix
    /// reaches — a cover is worth some work, not any amount of it.
    static func coverData(forEntry name: String, in outer: URL) -> Data? {
        guard let archive = try? ZipArchive.open(outer),
              let index = archive.index(of: name),
              let prefix = try? archive.data(at: index, byteLimit: coverPrefix)
        else { return nil }
        return ZipArchive.firstMember(inPrefix: prefix, where: ComicPageMeasure.isPage)
    }

    /// Enough for a first page of any ordinary size, and small enough that a shelf of
    /// them is not a wait.
    private static let coverPrefix = 6 * 1_024 * 1_024

    /// Keyed on where the outer archive is, how big it is, and which entry is wanted.
    ///
    /// The path and not just the name: two different downloads called `outer.zip` that
    /// happen to weigh the same would otherwise share a cache entry and show each
    /// other's pages. A test caught exactly that.
    private static func location(forEntry name: String, in outer: URL) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let size = (try? outer.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let digest = SHA256.hash(
            data: Data("\(outer.standardizedFileURL.path)|\(size)|\(name)".utf8)
        )
            .map { String(format: "%02x", $0) }
            .joined()
        return caches
            .appendingPathComponent(cacheFolderName, isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("\(digest).zip")
    }
}
