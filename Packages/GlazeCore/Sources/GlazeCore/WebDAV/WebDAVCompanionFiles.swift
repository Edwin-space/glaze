import Foundation

/// What sits next to a film in a folder listing.
///
/// This is the whole reason WebDAV is here. Over DLNA a film is `80.mkv` and there is
/// no way to ask what else shares its name; over WebDAV the folder listing is right
/// there, so the subtitle the Mac translated and the poster it fetched are simply two
/// more entries to pick out.
public struct WebDAVCompanions: Equatable, Sendable {
    public let subtitles: [WebDAVEntry]
    public let poster: WebDAVEntry?
    public let nfo: WebDAVEntry?

    public init(subtitles: [WebDAVEntry] = [], poster: WebDAVEntry? = nil, nfo: WebDAVEntry? = nil) {
        self.subtitles = subtitles
        self.poster = poster
        self.nfo = nfo
    }

    public var isEmpty: Bool {
        subtitles.isEmpty && poster == nil && nfo == nil
    }
}

public enum WebDAVCompanionFinder {
    /// - Parameters:
    ///   - video: the film to find companions for.
    ///   - siblings: everything else in the same folder, from one `PROPFIND`.
    public static func find(for video: WebDAVEntry, among siblings: [WebDAVEntry]) -> WebDAVCompanions {
        // The rule itself is shared with the local-folder loader; see
        // `MediaCompanionFinder`. Only the mapping back to entries is WebDAV's.
        let usable = siblings.filter { !$0.isDirectory && !$0.isHidden && $0.url != video.url }
        let names = MediaCompanionFinder.find(videoName: video.name, among: usable.map(\.name))
        let byName = Dictionary(usable.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        return WebDAVCompanions(
            subtitles: names.subtitles.compactMap { byName[$0] },
            poster: names.poster.flatMap { byName[$0] },
            nfo: names.nfo.flatMap { byName[$0] }
        )
    }
}
