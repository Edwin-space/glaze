import Foundation

/// Writes what was found out about a film next to the film.
///
/// Beside the video rather than inside it. Embedding is possible — the bundled ffmpeg
/// does it in about two seconds even for a 1.7GB file — but it rewrites the whole
/// container, needs the space, and can damage what was already in there: the first
/// attempt renamed the reference film's three embedded subtitle fonts to `cover.jpg`
/// (`docs/23`). Sidecars touch nothing.
///
/// The naming is Kodi's, which Jellyfin and Emby also read, so this is not a private
/// format anyone else has to be taught.
public struct MediaSidecarWriter: Sendable {
    public enum WriteError: Error, Sendable, Equatable {
        case notALocalFile
        case writeFailed
    }

    public init() {}

    /// - Returns: the files written, for reporting back to whoever asked.
    @discardableResult
    public func write(
        _ match: MediaMetadataMatch,
        poster: Data?,
        besideVideoAt videoURL: URL
    ) throws -> [URL] {
        guard videoURL.isFileURL else { throw WriteError.notALocalFile }

        var written: [URL] = []
        let base = videoURL.deletingPathExtension()

        let nfoURL = base.appendingPathExtension("nfo")
        do {
            try RelatedFileAccess.write(Data(nfo(for: match).utf8), to: nfoURL, relatedTo: videoURL)
            written.append(nfoURL)
        } catch {
            throw WriteError.writeFailed
        }

        if let poster {
            // `<name>-poster.jpg` is the form Kodi looks for first.
            let posterURL = URL(fileURLWithPath: base.path + "-poster.jpg")
            do {
                try RelatedFileAccess.write(poster, to: posterURL, relatedTo: videoURL)
                written.append(posterURL)
            } catch {
                // A missing poster is a worse-looking shelf, not a failed match; the
                // .nfo is already on disk and worth keeping.
            }
        }

        return written
    }

    /// Writes to wherever the film actually lives.
    ///
    /// - Parameter baseName: the film's filename without its extension; the sidecars
    ///   take the same stem, which is the whole convention.
    /// - Returns: the filenames written.
    @discardableResult
    public func write(
        _ match: MediaMetadataMatch,
        poster: Data?,
        baseName: String,
        to destination: some SidecarDestination
    ) async throws -> [String] {
        var written: [String] = []

        let nfoName = "\(baseName).nfo"
        do {
            try await destination.write(Data(nfo(for: match).utf8), named: nfoName)
            written.append(nfoName)
        } catch {
            throw WriteError.writeFailed
        }

        if let poster {
            let posterName = "\(baseName)-poster.jpg"
            do {
                try await destination.write(poster, named: posterName)
                written.append(posterName)
            } catch {
                // A missing poster is a worse-looking shelf, not a failed match; the
                // .nfo is already written and worth keeping.
            }
        }

        return written
    }

    /// Kodi's `movie.nfo`. Only the fields a provider actually gives us are written —
    /// an empty `<plot/>` is worse than no plot, because scrapers treat it as known.
    func nfo(for match: MediaMetadataMatch) -> String {
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>", "<movie>"]

        lines.append("  <title>\(escape(match.title))</title>")
        if let original = match.originalTitle, original != match.title {
            lines.append("  <originaltitle>\(escape(original))</originaltitle>")
        }
        if let year = match.year {
            lines.append("  <year>\(year)</year>")
        }
        if let overview = match.overview {
            lines.append("  <plot>\(escape(overview))</plot>")
        }
        if let rating = match.rating, rating > 0 {
            lines.append("  <rating>\(String(format: "%.1f", rating))</rating>")
        }
        for genre in match.genres {
            lines.append("  <genre>\(escape(genre))</genre>")
        }
        if let tmdbID = match.externalIDs.tmdbID {
            lines.append("  <uniqueid type=\"tmdb\">\(escape(tmdbID))</uniqueid>")
        }
        if let imdbID = match.externalIDs.imdbID {
            lines.append("  <uniqueid type=\"imdb\" default=\"true\">\(escape(imdbID))</uniqueid>")
        }

        lines.append("</movie>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Film titles carry ampersands and quotation marks often enough to matter, and an
    /// unescaped one makes the whole file unreadable rather than one field wrong.
    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
