import Foundation

/// Which files in a folder belong to a given video.
///
/// The rule lives here, on names alone, because two very different things ask it:
/// a WebDAV listing of a NAS folder, and a directory on the device itself. When it
/// lived only in the WebDAV code the local side had no way to find the subtitle the
/// Mac had written, which is the whole point of putting it beside the film.
public struct MediaCompanionNames: Equatable, Sendable {
    public let subtitles: [String]
    public let poster: String?
    public let nfo: String?

    public init(subtitles: [String] = [], poster: String? = nil, nfo: String? = nil) {
        self.subtitles = subtitles
        self.poster = poster
        self.nfo = nfo
    }

    public var isEmpty: Bool { subtitles.isEmpty && poster == nil && nfo == nil }
}

/// What Glaze treats as a film.
///
/// Matched on extension rather than on a content type: NAS servers routinely report
/// `application/octet-stream` for anything they do not recognise, and Matroska is
/// exactly the thing they do not recognise. The same list decides what a folder on
/// the device contains.
public enum MediaFileTypes {
    public static let video: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts", "wmv", "flv", "mpg", "mpeg"
    ]

    public static func isVideo(_ url: URL) -> Bool {
        video.contains(url.pathExtension.lowercased())
    }
}

public enum MediaCompanionFinder {
    public static let subtitleExtensions: Set<String> = ["srt", "vtt", "smi", "ass", "ssa"]
    public static let posterExtensions: Set<String> = ["jpg", "jpeg", "png"]

    /// - Parameters:
    ///   - videoName: the film's file name, with its extension.
    ///   - names: every other file name in the same folder.
    public static func find(videoName: String, among names: [String]) -> MediaCompanionNames {
        let base = stem(of: videoName)

        let related = names.filter { name in
            guard name != videoName else { return false }
            let candidate = stem(of: name)
            // `film.ko.srt` and `film-poster.jpg` both belong to `film.mkv`; the
            // separator differs by convention — subtitles use a dot, artwork a hyphen.
            // `film2.srt` belongs to neither, which is why the base has to be followed
            // by a separator rather than merely prefixed.
            return candidate == base
                || candidate.hasPrefix(base + ".")
                || candidate.hasPrefix(base + "-")
        }

        let subtitles = related.filter { subtitleExtensions.contains(extensionOf($0)) }.sorted()
        let images = related.filter { posterExtensions.contains(extensionOf($0)) }

        return MediaCompanionNames(
            subtitles: subtitles,
            poster: preferredPoster(from: images),
            nfo: related.first { extensionOf($0) == "nfo" }
        )
    }

    /// `film-poster.jpg` is what Glaze and Kodi write, so it wins over a stray
    /// screenshot that happens to share the name.
    private static func preferredPoster(from images: [String]) -> String? {
        images.first { stem(of: $0).hasSuffix("-poster") }
            ?? images.first { stem(of: $0).hasSuffix("-thumb") }
            ?? images.first
    }

    private static func stem(of name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    private static func extensionOf(_ name: String) -> String {
        (name as NSString).pathExtension.lowercased()
    }
}
