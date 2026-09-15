import Foundation
import UniformTypeIdentifiers

public struct MediaPlaylistItem: Identifiable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var id: String {
        url.absoluteString
    }

    public var displayName: String {
        url.lastPathComponent
    }
}

public enum MediaPlaylistBuilder {
    public static let supportedVideoExtensions: Set<String> = [
        "avi",
        "m4v",
        "mkv",
        "mov",
        "mp4",
        "mpeg",
        "mpg",
        "webm"
    ]

    public static func initialPlaylist(for url: URL) -> [MediaPlaylistItem] {
        guard !isDirectory(url), isVideoFile(url) else {
            return playlist(for: url)
        }

        return [MediaPlaylistItem(url: url)]
    }

    public static func playlist(for url: URL) -> [MediaPlaylistItem] {
        if isDirectory(url) {
            return videoFiles(in: url).map(MediaPlaylistItem.init(url:))
        }

        guard isVideoFile(url) else {
            return []
        }

        // The folder's own order, with the opened film wherever it falls in it. This used
        // to lift the opened film to the top — so opening episode two gave "2, 1, 3, 4",
        // "next" went back to episode one, and episode two had no "previous" at all.
        // The player finds its place by looking the film up, not by assuming it is first.
        let siblingVideos = videoFiles(in: url.deletingLastPathComponent())
        guard siblingVideos.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else {
            return ([url] + siblingVideos).map(MediaPlaylistItem.init(url:))
        }
        return siblingVideos.map(MediaPlaylistItem.init(url:))
    }

    public static func isVideoFile(_ url: URL) -> Bool {
        let extensionName = url.pathExtension.lowercased()
        guard !extensionName.isEmpty else {
            return false
        }

        if supportedVideoExtensions.contains(extensionName) {
            return true
        }

        guard let type = UTType(filenameExtension: extensionName) else {
            return false
        }

        return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent)
    }

    private static func videoFiles(in folderURL: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { isRegularFile($0) && isVideoFile($0) }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
    }
}
