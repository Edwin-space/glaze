import Foundation

enum PlaybackEngineKind: Equatable {
    case none
    case avkit
    case nativeMPV
}

enum PlaybackEngineRouter {
    static func preferredEngine(for url: URL) -> PlaybackEngineKind {
        if nativeEngineContainers.contains(url.pathExtension.lowercased()) {
            return .nativeMPV
        }

        return .avkit
    }

    static var nativeEngineContainers: Set<String> {
        ["mkv", "webm", "avi"]
    }
}
