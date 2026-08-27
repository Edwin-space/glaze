import Foundation

/// Where a subtitle Glaze produced should be written.
///
/// "Local" and "network" is a false distinction on macOS: a NAS mounted over SMB is
/// an ordinary path, so saving beside the video already saves to the NAS. That is why
/// beside-the-video is the default — it puts the subtitle where the video is, where
/// other devices and other players can find it.
public enum SubtitleStorageLocation: String, Equatable, Sendable, CaseIterable, Codable {
    /// Next to the video, as a sidecar file.
    case besideVideo
    /// Inside the app's own storage, leaving the video's folder untouched.
    case appLibrary

    public static let `default` = SubtitleStorageLocation.besideVideo

    public var labelKey: String {
        switch self {
        case .besideVideo: "subtitle.storage.beside_video"
        case .appLibrary: "subtitle.storage.app_library"
        }
    }
}

public enum SubtitleStoreError: Error, Equatable, Sendable {
    /// The resource has no writable file location — a stream, for instance.
    case noWritableLocation
    case writeFailed
}

/// Writes finished subtitles somewhere they can be found again.
///
/// A protocol rather than a function because the destination is going to grow: beside
/// the video today, a NAS upload or iCloud sync later (`21_media_server_vision.md`).
/// Keyed on `MediaResource` rather than a local `URL` for the same reason — a video
/// streamed from a server has no local path to key on.
public protocol SubtitleStoring: Sendable {
    /// - Returns: where the subtitle was written.
    @discardableResult
    func save(
        cues: [SubtitleCue],
        for resource: MediaResource,
        kind: SubtitleArtifactKind,
        preferring location: SubtitleStorageLocation
    ) throws -> URL
}

/// What produced the subtitle, which decides the filename suffix so a generated
/// original and its translation can sit side by side without colliding.
public enum SubtitleArtifactKind: Equatable, Sendable {
    case generated(languageCode: String?)
    case translated(languageCode: String)

    /// The suffix between the film's name and `.srt`.
    ///
    /// Follows the convention Jellyfin, Emby and Kodi all read: `Film.ko.srt` is a
    /// Korean subtitle for `Film.mkv`. The earlier form was `Film.original.ko.srt`,
    /// which no scraper understands and which says two contradictory things — it is
    /// not the original if it is in Korean.
    ///
    /// A transcription is labelled with the language that was spoken, when Whisper
    /// reported one, so a server shelving it knows what it is.
    public var filenameSuffix: String {
        switch self {
        case .generated(let languageCode):
            Self.filenameLanguageCode(languageCode)
        case .translated(let languageCode):
            Self.filenameLanguageCode(languageCode)
        }
    }

    /// Keep filenames predictable even when a framework reports a regional or
    /// three-letter tag. Sidecar consumers agree much more reliably on the normalized
    /// ISO language (`ja`, `ko`) than on aliases (`jpn`, `kor`) or regions (`ko-KR`).
    private static func filenameLanguageCode(_ value: String?) -> String {
        guard let normalized = SubtitleLanguageCode.normalized(value),
              Locale.LanguageCode(normalized).isISOLanguage else {
            return "und"
        }

        return normalized
    }
}

/// Writes SRT files to disk, beside the video when that is possible and permitted.
public struct FileSubtitleStore: SubtitleStoring {
    /// Where `appLibrary` writes. Injected so tests do not touch the real library.
    public let libraryDirectory: URL

    public init(libraryDirectory: URL) {
        self.libraryDirectory = libraryDirectory
    }

    @discardableResult
    public func save(
        cues: [SubtitleCue],
        for resource: MediaResource,
        kind: SubtitleArtifactKind,
        preferring location: SubtitleStorageLocation
    ) throws -> URL {
        let candidates = destinations(for: resource, kind: kind, preferring: location)
        guard !candidates.isEmpty else { throw SubtitleStoreError.noWritableLocation }

        // Only a local file has a video for the sandbox to relate the write to.
        let videoURL: URL? = if case .localFile(let url) = resource { url } else { nil }

        var lastError: Error?
        for destination in candidates {
            do {
                try SubtitleWriter.writeSRT(cues: cues, to: destination, relatedTo: videoURL)
                return destination
            } catch {
                // Beside-the-video can fail on a read-only volume or a folder the
                // sandbox will not grant; fall through to app storage rather than
                // losing work the user waited for.
                lastError = error
            }
        }

        throw lastError.map { _ in SubtitleStoreError.writeFailed } ?? SubtitleStoreError.writeFailed
    }

    /// Ordered by preference, so the caller can fall back without deciding policy.
    func destinations(
        for resource: MediaResource,
        kind: SubtitleArtifactKind,
        preferring location: SubtitleStorageLocation
    ) -> [URL] {
        let library = libraryDestination(for: resource, kind: kind)

        guard location == .besideVideo, let beside = besideVideoDestination(for: resource, kind: kind) else {
            return [library]
        }

        return [beside, library]
    }

    private func besideVideoDestination(for resource: MediaResource, kind: SubtitleArtifactKind) -> URL? {
        // Only a real file has a folder to sit beside. A streamed resource does not.
        guard case .localFile(let videoURL) = resource, videoURL.isFileURL else { return nil }
        return videoURL
            .deletingPathExtension()
            .appendingPathExtension(kind.filenameSuffix)
            .appendingPathExtension("srt")
    }

    private func libraryDestination(for resource: MediaResource, kind: SubtitleArtifactKind) -> URL {
        libraryDirectory
            .appendingPathComponent(Self.identifier(for: resource))
            .appendingPathExtension(kind.filenameSuffix)
            .appendingPathExtension("srt")
    }

    /// A stable name for a resource inside the app library.
    ///
    /// A streamed video has no path, so the filename cannot come from one. The
    /// server-scoped object id is what stays the same across sessions.
    static func identifier(for resource: MediaResource) -> String {
        switch resource {
        case .localFile(let url):
            url.deletingPathExtension().lastPathComponent
        case .network(let networkResource):
            "\(networkResource.serverID)-\(networkResource.objectID)"
                .replacingOccurrences(of: "/", with: "-")
        }
    }
}
