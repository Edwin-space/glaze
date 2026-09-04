import Foundation

public enum PlaybackEngineKind: Equatable, Sendable {
    case none
    case avkit
    case nativeVLC
}

public enum PlaybackEngineRouter {
    /// Anything streamed goes to VLC, whatever the address looks like.
    ///
    /// Choosing by file extension worked for files and failed for servers: a DLNA
    /// playback address is an object id — `/o/v/80` — with no extension to read, so a
    /// 4K MKV on a NAS was handed to AVKit, which cannot open it. The failure then fell
    /// back to remuxing the entire stream through ffmpeg into a local file, which is
    /// why such a film stalled on opening and would not seek until enough of it had
    /// been rewritten. VLC plays the stream directly, which is what a NAS needs.
    public static func preferredEngine(for resource: MediaResource) -> PlaybackEngineKind {
        switch resource {
        case .network:
            .nativeVLC
        case .localFile(let url):
            preferredEngine(for: url)
        }
    }

    public static func preferredEngine(for url: URL) -> PlaybackEngineKind {
        // A remote address that does carry a filename is still remote; only a real file
        // on disk is a candidate for AVKit's cheaper hardware path.
        if !url.isFileURL {
            return .nativeVLC
        }

        if nativeEngineContainers.contains(url.pathExtension.lowercased()) {
            return .nativeVLC
        }

        return .avkit
    }

    public static var nativeEngineContainers: Set<String> {
        ["mkv", "webm", "avi", "mp4", "m4v", "mov", "wmv", "flv", "ts", "m2ts", "mpg", "mpeg", "3gp", "ogv"]
    }
}
