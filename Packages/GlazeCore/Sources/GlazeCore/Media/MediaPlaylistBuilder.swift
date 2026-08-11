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

        let siblingVideos = videoFiles(in: url.deletingLastPathComponent())
        let orderedVideos = [url] + siblingVideos.filter { $0.standardizedFileURL != url.standardizedFileURL }
        return orderedVideos.map(MediaPlaylistItem.init(url:))
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
