import Foundation

enum PlaybackEngineKind: Equatable {
    case none
    case avkit
    case nativeVLC
}

enum PlaybackEngineRouter {
    static func preferredEngine(for url: URL) -> PlaybackEngineKind {
        if nativeEngineContainers.contains(url.pathExtension.lowercased()) {
            return .nativeVLC
        }

        return .avkit
    }

    static var nativeEngineContainers: Set<String> {
        ["mkv", "webm", "avi", "mp4", "m4v", "mov", "wmv", "flv", "ts", "m2ts", "mpg", "mpeg", "3gp", "ogv"]
    }
}
