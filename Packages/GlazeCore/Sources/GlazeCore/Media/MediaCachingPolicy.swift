import Foundation

/// How much of a film to hold in front of the decoder.
///
/// The buffer was set to 300ms for streams and 100ms for files, both far below VLC's
/// own defaults. On a 40Mbps 4K remux that is under two megabytes: any hesitation on
/// the network starves the decoder, which is what a stall looks like, and a seek is
/// worse still because the buffer has to be refilled from nothing before a frame can
/// be shown. Small buffers only ever helped local files, which do not need the help.
///
/// A mounted share counts as remote. `/Volumes/NAS/Film.mkv` is a file URL and was
/// getting the file buffer, but the bytes still cross the same network.
public enum MediaCachingPolicy: Sendable {
    /// VLC's own default for files. There is nothing to gain by going below it.
    public static let localMilliseconds = 300
    /// Three seconds of a high-bitrate 4K stream. Costs a moment at startup and after
    /// a seek; the alternative is a film that stops every few seconds.
    public static let remoteMilliseconds = 3_000

    public static func cachingMilliseconds(for url: URL) -> Int {
        isRemote(url) ? remoteMilliseconds : localMilliseconds
    }

    public static func isRemote(_ url: URL) -> Bool {
        guard url.isFileURL else { return true }
        // The boot volume is the only place a file is certainly local. Everything under
        // /Volumes is a mount, and the ones that matter here are network shares.
        return url.standardizedFileURL.path.hasPrefix("/Volumes/")
    }

    /// The `:option=value` forms libVLC takes per media item.
    public static func mediaOptions(for url: URL) -> [String] {
        let milliseconds = cachingMilliseconds(for: url)
        return [":file-caching=\(milliseconds)", ":network-caching=\(milliseconds)"]
    }
}
