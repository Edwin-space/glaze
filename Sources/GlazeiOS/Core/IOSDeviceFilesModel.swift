import Foundation
import GlazeBooks
import GlazeCore
import Observation

/// A file the viewer put on the phone themselves.
struct IOSDeviceFile: Identifiable, Equatable {
    enum Kind: Equatable {
        case video
        case book(BookItem.Kind)
    }

    let url: URL
    let kind: Kind
    let byteCount: Int64
    /// How many subtitle files sit beside it. Always zero for a book.
    let subtitleCount: Int

    var id: String { url.standardizedFileURL.absoluteString }
    var name: String { url.lastPathComponent }

    var symbol: String {
        switch kind {
        case .video: "film"
        case .book(.comic): "book.pages"
        case .book(.document): "doc.richtext"
        case .book(.ebook): "text.book.closed"
        }
    }
}

/// What is in the app's own folder, and how to put things there or take them away.
///
/// This is the file side of the device library — the list, the sizes, the deleting.
/// Reading them *as films* is `LocalLibraryLoader`'s job.
@Observable
@MainActor
final class IOSDeviceFilesModel {
    private(set) var files: [IOSDeviceFile] = []
    private(set) var isWorking = false
    private(set) var failure: String?

    var totalByteCount: Int64 { files.reduce(0) { $0 + $1.byteCount } }
    var isEmpty: Bool { files.isEmpty }

    var videos: [IOSDeviceFile] { files.filter { $0.kind == .video } }
    var bookCount: Int { files.count - videos.count }

    var root: URL { IOSLibraryModel.deviceLibraryURL }

    func reload() {
        let root = self.root
        let found = Self.scan(root)
        files = found
    }

    /// Copies a file the viewer picked into the app's folder, so it stays put and
    /// works with no server and no network.
    func importFile(from source: URL) {
        isWorking = true
        defer { isWorking = false }

        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let destination = uniqueDestination(for: source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            reload()
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Removes the film and whatever was sitting beside it, so deleting does not
    /// leave orphaned subtitles and posters behind.
    func delete(_ file: IOSDeviceFile) {
        let folder = file.url.deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let companions = MediaCompanionFinder.find(videoName: file.name, among: siblings)

        var doomed = [file.url]
        doomed += companions.subtitles.map(folder.appendingPathComponent)
        doomed += [companions.poster, companions.nfo].compactMap { $0 }.map(folder.appendingPathComponent)

        for url in doomed {
            try? FileManager.default.removeItem(at: url)
        }
        reload()
    }

    func clearFailure() { failure = nil }

    // MARK: - Reading

    private func uniqueDestination(for name: String) -> URL {
        var candidate = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let stem = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        var index = 2
        repeat {
            let next = suffix.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(suffix)"
            candidate = root.appendingPathComponent(next)
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func scan(_ root: URL) -> [IOSDeviceFile] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [(url: URL, kind: IOSDeviceFile.Kind)] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            guard !url.lastPathComponent.hasPrefix("._") else { continue }
            if MediaFileTypes.isVideo(url) {
                found.append((url, .video))
            } else if let kind = BookFileTypes.kind(of: url) {
                found.append((url, .book(kind)))
            }
        }

        return found
            .map { entry in
                let url = entry.url
                let folder = url.deletingLastPathComponent()
                let siblings = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                let companions = MediaCompanionFinder.find(videoName: url.lastPathComponent, among: siblings)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return IOSDeviceFile(
                    url: url,
                    kind: entry.kind,
                    byteCount: Int64(size),
                    // A book has no subtitle sitting beside it; the companion rule is
                    // only asked about films.
                    subtitleCount: entry.kind == .video ? companions.subtitles.count : 0
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
