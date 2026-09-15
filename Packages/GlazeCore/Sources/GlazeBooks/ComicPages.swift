import CoreGraphics
import Foundation
import ImageIO

/// Somewhere a comic's pages come from.
///
/// A `.cbz` reads pages straight out of the zip. A `.7z` cannot: it is solid-
/// compressed, so reaching page five hundred means decoding everything before it.
/// That one is unpacked to disk first and read as a folder. The reader should not
/// have to know which it got.
public protocol ComicPages: Sendable {
    var pageCount: Int { get }
    /// The image bytes for one page.
    func imageData(at index: Int) throws -> Data
    /// How big a page is, without drawing it.
    func pageSize(at index: Int) -> CGSize?
}

/// Reads an image's dimensions from its own header rather than by decoding it.
///
/// A vertical strip needs every page's height before it can lay anything out, and
/// decoding a whole volume to find that out would defeat the point.
enum ComicPageMeasure {
    /// Most formats declare their size in the first few kilobytes; a JPEG carrying an
    /// EXIF thumbnail can push it further back, which is what the second size is for.
    static let headerReadSizes = [32_768, 262_144]

    static func size(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "tif", "tiff", "avif"
    ]

    /// Files that are pages, and files that merely travel with them.
    static func isPage(_ name: String) -> Bool {
        guard !name.hasSuffix("/") else { return false }
        guard !name.contains("__MACOSX") else { return false }
        let file = (name as NSString).lastPathComponent
        guard !file.hasPrefix("."), !file.hasPrefix("._") else { return false }
        return imageExtensions.contains((file as NSString).pathExtension.lowercased())
    }
}

/// A folder of images, read as a comic.
///
/// Two things arrive this way: a folder someone unzipped themselves, and a `.7z`
/// this app unpacked for them.
public struct ComicFolder: ComicPages {
    public let root: URL
    /// In reading order, sorted the way a person numbers files.
    public let pages: [URL]

    public var pageCount: Int { pages.count }

    public enum Failure: Error, Equatable {
        case noPages
    }

    public init(root: URL) throws {
        self.root = root
        pages = Self.pages(in: root)
        guard !pages.isEmpty else { throw Failure.noPages }
    }

    public func imageData(at index: Int) throws -> Data {
        guard pages.indices.contains(index) else { throw Failure.noPages }
        return try Data(contentsOf: pages[index], options: .mappedIfSafe)
    }

    public func pageSize(at index: Int) -> CGSize? {
        guard pages.indices.contains(index),
              let handle = try? FileHandle(forReadingFrom: pages[index]) else { return nil }
        defer { try? handle.close() }

        for limit in ComicPageMeasure.headerReadSizes {
            guard let data = try? handle.read(upToCount: limit) else { return nil }
            if let size = ComicPageMeasure.size(from: data) { return size }
            if data.count < limit { return nil }
            try? handle.seek(toOffset: 0)
        }
        return nil
    }

    /// Every image below the folder, in reading order.
    public static func pages(in root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker where ComicPageMeasure.isPage(url.lastPathComponent) {
            found.append(url)
        }
        // Compared on the path so `ch02/001` follows `ch01/999`, and numbered the way
        // a person reads numbers.
        return found.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    /// The folders directly inside that each hold a volume's worth of pages.
    /// Empty when the folder is one book, which is the ordinary case.
    public static func volumes(in root: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let withPages = entries.filter { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            return !pages(in: entry).isEmpty
        }
        guard withPages.count > 1 else { return [] }
        return withPages
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
