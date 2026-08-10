import Foundation

public enum PlaybackEngineKind: Equatable, Sendable {
    case none
    case avkit
    case nativeVLC
}

public enum PlaybackEngineRouter {
    public static func preferredEngine(for url: URL) -> PlaybackEngineKind {
        if nativeEngineContainers.contains(url.pathExtension.lowercased()) {
            return .nativeVLC
        }

        return .avkit
    }

    public static var nativeEngineContainers: Set<String> {
        ["mkv", "webm", "avi", "mp4", "m4v", "mov", "wmv", "flv", "ts", "m2ts", "mpg", "mpeg", "3gp", "ogv"]
    }
}
