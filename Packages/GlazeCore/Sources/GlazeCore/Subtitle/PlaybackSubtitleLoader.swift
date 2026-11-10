import Foundation

public struct PreparedPlaybackSubtitle: Sendable {
    public let resource: NetworkSubtitleResource
    public let timeline: SubtitleTimeline
}

/// Network transfer and parsing stay off the main actor. Video opening never waits
/// for this operation. A DSM download URL may end in entry.cgi, not in .srt.
public actor PlaybackSubtitleLoader {
    private let network: NetworkSubtitleLoader

    public init(network: NetworkSubtitleLoader = NetworkSubtitleLoader()) {
        self.network = network
    }

    public nonisolated static func supports(_ resource: NetworkSubtitleResource) -> Bool {
        let name = resource.displayName.isEmpty ? resource.url.lastPathComponent : resource.displayName
        return URL(fileURLWithPath: name).pathExtension.lowercased() == "srt"
    }

    public func prepare(_ resource: NetworkSubtitleResource) async throws -> PreparedPlaybackSubtitle {
        let local: URL
        if resource.url.isFileURL {
            local = resource.url
        } else {
            local = try await network.load(resource)
        }
        try Task.checkCancellation()
        let size = try local.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 16 * 1_024 * 1_024 else { throw NetworkSubtitleLoader.LoaderError.responseTooLarge }
        let cues: [SubtitleCue]
        do {
            cues = try SubtitleParser.parse(url: local)
        } catch {
            // An HTML error returned as HTTP 200 must not poison every retry until
            // TTL expiry. Deleting a bad local cache never deletes the NAS source.
            if !resource.url.isFileURL { await network.invalidate(resource) }
            throw error
        }
        try Task.checkCancellation()
        return PreparedPlaybackSubtitle(resource: resource, timeline: SubtitleTimeline(cues: cues))
    }
}
