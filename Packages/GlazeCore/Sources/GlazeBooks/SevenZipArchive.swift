import Foundation
import SWCompression

/// A `.7z` holding a comic.
///
/// Unlike a zip, 7-Zip compresses solidly: files share one compressed stream, so
/// reaching page five hundred means decoding everything before it. Reading pages on
/// demand — which is what makes a four-hundred-page `.cbz` cheap — is not available
/// here. So a `.7z` is unpacked once into the caches folder and read as a folder
/// after that.
///
/// The decoder is SWCompression: pure Swift and MIT, which is the whole reason 7-Zip
/// is supported and RAR is not (`docs/33`).
public enum SevenZipArchive {
    public enum Failure: Error, Equatable {
        case unreadable
        case noPages
        /// The archive uses a codec this decoder does not read — BCJ2 most often.
        /// Rare in comic archives, which are written with LZMA2, but it happens, and
        /// "could not open" would send someone looking for a damaged file.
        case compressionNotSupported
    }

    /// The names inside, without decompressing anything but the header.
    ///
    /// Cheap enough to run over every `.7z` on the device while building the shelf.
    public static func entryNames(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let entries = try? SevenZipContainer.info(container: data)
        else { return [] }
        return entries.filter { $0.type != .directory }.map(\.name)
    }

    /// Whether the archive holds any pages — what tells a comic from the many other
    /// things a `.7z` can be.
    public static func holdsPages(at url: URL) -> Bool {
        entryNames(at: url).contains(where: ComicPageMeasure.isPage)
    }

    /// The folders inside that each hold a volume's worth of pages.
    public static func volumes(at url: URL) -> [String] {
        var byFolder: [String: Int] = [:]
        for name in entryNames(at: url) where ComicPageMeasure.isPage(name) {
            let parts = name.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            guard parts.count > 1 else { continue }
            byFolder[String(parts[0]), default: 0] += 1
        }
        guard byFolder.count > 1 else { return [] }
        return byFolder.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Unpacks the pages into a folder.
    ///
    /// Everything at once, because the format gives no cheaper option: pulling out one
    /// volume would decode most of the archive anyway, and doing that per volume would
    /// pay the cost again every time.
    ///
    /// - Parameter onProgress: pages written so far, and how many there are.
    public static func extract(
        at url: URL,
        to directory: URL,
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw Failure.unreadable
        }
        let entries: [SevenZipEntry]
        do {
            entries = try SevenZipContainer.open(container: data)
        } catch SevenZipError.compressionNotSupported {
            throw Failure.compressionNotSupported
        } catch {
            throw Failure.unreadable
        }

        let pages = entries.filter { $0.info.type != .directory && ComicPageMeasure.isPage($0.info.name) }
        guard !pages.isEmpty else { throw Failure.noPages }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var written = 0
        for entry in pages {
            guard let contents = entry.data else { continue }
            // 7-Zip records Windows separators, and a name climbing out of the folder
            // would write anywhere on the disk.
            let relative = entry.info.name
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .filter { $0 != ".." && $0 != "." }
                .joined(separator: "/")
            guard !relative.isEmpty else { continue }

            let destination = directory.appendingPathComponent(relative)
            guard destination.standardizedFileURL.path
                .hasPrefix(directory.standardizedFileURL.path) else { continue }

            try? fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: destination, options: Data.WritingOptions.atomic)
            written += 1
            onProgress?(written, pages.count)
        }
        guard written > 0 else { throw Failure.noPages }
    }
}
