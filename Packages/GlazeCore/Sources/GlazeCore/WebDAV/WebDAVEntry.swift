import Foundation

/// One thing in a WebDAV folder.
///
/// The reason WebDAV is here at all is the name. DLNA hands out opaque playback URLs —
/// `80.mkv`, `file.mkv` — so nothing beside the video can be found from one, which is
/// why sidecar subtitles and posters do not work over it (`docs/22`, `docs/23`).
/// WebDAV gives back the real path, and everything next to the film follows.
public struct WebDAVEntry: Identifiable, Equatable, Sendable {
    public let url: URL
    /// The filename as the server spells it, already percent-decoded.
    public let name: String
    public let isDirectory: Bool
    public let byteCount: Int64?
    public let contentType: String?
    public let lastModified: Date?

    public var id: String { url.absoluteString }

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        byteCount: Int64? = nil,
        contentType: String? = nil,
        lastModified: Date? = nil
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.byteCount = byteCount
        self.contentType = contentType
        self.lastModified = lastModified
    }

    /// Housekeeping the filesystem left behind rather than something to watch.
    ///
    /// A Mac writing to a share leaves an AppleDouble `._Film.mkv` beside every file it
    /// touches. It carries the video extension, so it was being listed as a film,
    /// counted as an episode, and — worse — given the show's poster, which then hung
    /// off a file nothing else refers to.
    public var isHidden: Bool {
        if name.hasPrefix(".") { return true }
        return Self.skippedNames.contains(name.lowercased())
    }

    /// Folders a NAS keeps for itself.
    ///
    /// `@eaDir` is where Synology puts a thumbnail for every file it has ever indexed,
    /// and it appears beside almost everything; walking into those turns a library scan
    /// into a scan of the whole disk. `#recycle` is the share's wastebasket, and a film
    /// deleted last year is not part of the library.
    static let skippedNames: Set<String> = [
        "@eadir", "#recycle", "@recycle", "#snapshot", "lost+found",
        "thumbs.db", "desktop.ini", "$recycle.bin", "system volume information"
    ]

    /// Whether this is a film worth listing.
    public var isVideo: Bool {
        !isHidden && Self.videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// Matched on extension rather than the server's content type: NAS servers routinely
    /// report `application/octet-stream` for anything they do not recognise, and
    /// Matroska is exactly the thing they do not recognise.
    static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts", "wmv", "flv", "mpg", "mpeg"
    ]
}
