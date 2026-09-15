import CoreGraphics
import GlazeCore
import Foundation
import ImageIO

/// A `.cbz` comic: one image per page, in a zip.
///
/// The zip itself is `ZipArchive`'s job. What is left here is the part that makes a
/// comic a comic — which members count as pages, what order a person reads them in,
/// and how big each one is.
public struct ComicArchive: ComicPages {
    public struct Page: Equatable, Sendable {
        /// The full path inside the archive, e.g. `ch01/007.jpg`.
        public let name: String
        /// Where it sits in the zip's own listing.
        fileprivate let entryIndex: Int
    }

    public enum Failure: Error, Equatable {
        case unreadable
        case notAZip
        case noPages
        case damagedPage(String)
    }

    private let archive: ZipArchive
    /// In reading order, sorted the way a person numbers files.
    public let pages: [Page]
    /// Which part of the archive these pages came from, when it holds more than one
    /// volume. Nil when the whole archive is one book.
    public let section: String?

    public var url: URL { archive.url }
    public var pageCount: Int { pages.count }

    // MARK: - Opening

    /// Reads the archive's table of contents. Does not read any page.
    ///
    /// - Parameter section: the folder inside the archive to read, when it holds a
    ///   run of volumes rather than one book.
    public static func open(_ url: URL, section: String? = nil) throws -> ComicArchive {
        // A section that names an inner archive is a volume in a zip-of-zips. The
        // inner archive is inflated to the caches folder and then read as any other,
        // so everything below this line is the ordinary path.
        if let section, NestedZipCache.isArchive(section) {
            guard let inner = NestedZipCache.file(forEntry: section, in: url) else {
                throw Failure.unreadable
            }
            let opened = try open(inner)
            return ComicArchive(archive: opened.archive, pages: opened.pages, section: section)
        }

        let archive: ZipArchive
        do {
            archive = try ZipArchive.open(url)
        } catch ZipArchive.Failure.unreadable {
            throw Failure.unreadable
        } catch {
            throw Failure.notAZip
        }

        var pages = archive.entries.enumerated()
            .filter { isPage($0.element.name) }
            .map { Page(name: $0.element.name, entryIndex: $0.offset) }

        if let section {
            pages = pages.filter { volumeFolder(of: $0.name) == section }
        }
        pages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        guard !pages.isEmpty else { throw Failure.noPages }
        return ComicArchive(archive: archive, pages: pages, section: section)
    }

    /// The folders inside an archive that each hold a volume's worth of pages.
    ///
    /// A download is routinely one archive called `1~24권` with a folder per volume.
    /// Read as a single book that is five thousand pages with no chapter breaks;
    /// read as folders it is the run it actually is. Returns empty when the archive
    /// is one book, which is the ordinary case.
    public static func volumes(in url: URL) -> [String] {
        guard let archive = try? ZipArchive.open(url) else { return [] }

        var byFolder: [String: Int] = [:]
        for entry in archive.entries where isPage(entry.name) {
            guard let folder = volumeFolder(of: entry.name) else { continue }
            byFolder[folder, default: 0] += 1
        }
        // One folder is just how someone zipped a single volume; two or more is a run.
        if byFolder.count > 1 {
            return byFolder.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        // Archives inside it: a zip-of-zips, one per volume. Even a single inner
        // archive counts — the outer zip is then a wrapper around one volume rather
        // than a book in its own right.
        //
        // These win over any loose image at the top level. Half of these downloads
        // carry a `[Cover].jpg` next to the volumes, and treating that one file as
        // the archive's pages turned a twenty-volume run into a one-page book.
        let nested = archive.entries.map(\.name).filter(NestedZipCache.isArchive)
        return nested.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The first page, for a thumbnail, at the least cost that will produce one.
    ///
    /// A volume inside a zip-of-zips is *not* extracted for this. The shelf draws a
    /// cover for every volume of every run — seventy-four of them for one download on
    /// the phone this was written for — and inflating each inner archive in full to
    /// take one picture out of it wrote over a gigabyte to the caches folder and made
    /// opening the shelf a wait. Only the front of the inner archive is read, which is
    /// where its first page happens to live.
    public static func coverData(of url: URL, section: String?) -> Data? {
        guard let section, NestedZipCache.isArchive(section) else {
            return try? ComicArchive.open(url, section: section).imageData(at: 0)
        }
        // Already unpacked because someone read this volume: use it and skip the work.
        if let cached = NestedZipCache.existingFile(forEntry: section, in: url) {
            return try? ComicArchive.open(cached).imageData(at: 0)
        }
        return NestedZipCache.coverData(forEntry: section, in: url)
    }

    /// Whether an archive holds any pages at all — what tells a comic `.zip` from
    /// the many other things a `.zip` can be.
    public static func holdsPages(_ url: URL) -> Bool {
        guard let archive = try? ZipArchive.open(url) else { return false }
        // Archives inside count too, and are checked from the outer listing alone —
        // deciding by opening every inner volume would put the cost of the whole
        // library back into the scan, which is what this avoids.
        return archive.entries.contains { isPage($0.name) || NestedZipCache.isArchive($0.name) }
    }

    /// The first path component, when the page is not loose at the top level.
    private static func volumeFolder(of name: String) -> String? {
        let parts = name.split(separator: "/")
        guard parts.count > 1 else { return nil }
        return String(parts[0])
    }

    // MARK: - Reading a page

    /// The image bytes for one page, decompressed.
    public func imageData(at index: Int) throws -> Data {
        try imageData(at: index, byteLimit: nil)
    }

    /// - Parameter byteLimit: stop after this many decompressed bytes.
    public func imageData(at index: Int, byteLimit: Int?) throws -> Data {
        guard pages.indices.contains(index) else { throw Failure.noPages }
        let page = pages[index]
        do {
            return try archive.data(at: page.entryIndex, byteLimit: byteLimit)
        } catch {
            throw Failure.damagedPage(page.name)
        }
    }

    /// How big a page is, without drawing it.
    ///
    /// Read from the image's own header rather than by decoding: a vertical strip
    /// needs every page's height before it can lay anything out, and decoding the
    /// whole volume to find out would defeat the point.
    public func pageSize(at index: Int) -> CGSize? {
        for limit in Self.headerReadSizes {
            guard let data = try? imageData(at: index, byteLimit: limit) else { return nil }
            if let size = Self.imageSize(from: data) { return size }
            // The whole page is already in hand and still says nothing; reading more
            // will not help.
            if data.count < limit { return nil }
        }
        return (try? imageData(at: index)).flatMap(Self.imageSize)
    }

    private static func imageSize(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Most formats declare their size in the first few kilobytes; a JPEG carrying an
    /// EXIF thumbnail can push it further back, which is what the second size is for.
    private static let headerReadSizes = [32_768, 262_144]

    // MARK: - What counts as a page

    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "tif", "tiff"
    ]

    private static func isPage(_ name: String) -> Bool {
        guard !name.hasSuffix("/") else { return false }
        guard !name.contains("__MACOSX") else { return false }
        let file = (name as NSString).lastPathComponent
        guard !file.hasPrefix("."), !file.hasPrefix("._") else { return false }
        return imageExtensions.contains((file as NSString).pathExtension.lowercased())
    }
}
