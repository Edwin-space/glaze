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
    private static let subtitleExtensions: Set<String> = ["srt", "vtt", "smi", "ass", "ssa"]
    private static let posterExtensions: Set<String> = ["jpg", "jpeg", "png"]

    /// - Parameters:
    ///   - video: the film to find companions for.
    ///   - siblings: everything else in the same folder, from one `PROPFIND`.
    public static func find(for video: WebDAVEntry, among siblings: [WebDAVEntry]) -> WebDAVCompanions {
        let base = stem(of: video.name)

        let related = siblings.filter { entry in
            guard !entry.isDirectory, !entry.isHidden, entry.url != video.url else { return false }
            let entryStem = stem(of: entry.name)
            // `film.ko.srt` and `film-poster.jpg` both belong to `film.mkv`; the
            // separator differs by convention — subtitles use a dot, artwork a hyphen.
            // `film2.srt` belongs to neither, which is why the base has to be followed
            // by a separator rather than merely prefixed.
            return entryStem == base
                || entryStem.hasPrefix(base + ".")
                || entryStem.hasPrefix(base + "-")
        }

        let subtitles = related.filter { subtitleExtensions.contains($0.url.pathExtension.lowercased()) }
        let images = related.filter { posterExtensions.contains($0.url.pathExtension.lowercased()) }

        return WebDAVCompanions(
            subtitles: subtitles.sorted { $0.name < $1.name },
            poster: preferredPoster(from: images),
            nfo: related.first { $0.url.pathExtension.lowercased() == "nfo" }
        )
    }

    /// `film-poster.jpg` is what Glaze and Kodi write, so it wins over a stray
    /// screenshot that happens to share the name.
    private static func preferredPoster(from images: [WebDAVEntry]) -> WebDAVEntry? {
        images.first { stem(of: $0.name).hasSuffix("-poster") }
            ?? images.first { stem(of: $0.name).hasSuffix("-thumb") }
            ?? images.first
    }

    /// The name with its final extension removed — `film.ko.srt` gives `film.ko`.
    private static func stem(of name: String) -> String {
        (name as NSString).deletingPathExtension
    }
}
