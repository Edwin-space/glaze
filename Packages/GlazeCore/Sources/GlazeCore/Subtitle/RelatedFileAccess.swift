import Foundation

/// One place where subtitle files are read and written.
///
/// Under the App Sandbox, opening a film grants access to that one file — not the
/// `.srt` beside it, which is how sidecar subtitles have always worked. Reading it is
/// refused, and the unsandboxed Debug build never sees the problem.
///
/// Three things together make it work, and each covers what the others miss:
///
/// 1. `com.apple.security.assets.movies.read-write` opens `~/Movies` with nothing to
///    ask. Films kept there — the default place — just work.
/// 2. `SubtitleFolderAccess` asks for any other folder once and keeps the grant, which
///    is what covers the Desktop, an external drive, and the mounted NAS share this
///    product is headed toward.
/// 3. The file coordination here, which declares the subtitle a related item of the
///    video. On its own it is *not* sufficient — measured against a signed, sandboxed
///    build, the read still failed — but it is correct, cheap, and the right thing to
///    be doing when a coordinated write lands beside a file another process holds.
public enum RelatedFileAccess {
    /// - Parameter primaryURL: the video the file belongs to. nil skips coordination,
    ///   for files the app reached some other way — its own library, or one the viewer
    ///   picked from an open panel.
    public static func read(_ url: URL, relatedTo primaryURL: URL?) throws -> Data {
        try coordinate(url, relatedTo: primaryURL) { coordinator, presenter in
            var coordinationError: NSError?
            var outcome: Result<Data, Error>?

            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { granted in
                outcome = Result { try Data(contentsOf: granted) }
            }

            if let coordinationError { throw coordinationError }
            return try outcome?.get() ?? Data()
        }
    }

    public static func write(_ data: Data, to url: URL, relatedTo primaryURL: URL?) throws {
        try coordinate(url, relatedTo: primaryURL) { coordinator, presenter in
            var coordinationError: NSError?
            var writeError: Error?

            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { granted in
                do {
                    try data.write(to: granted, options: .atomic)
                } catch {
                    writeError = error
                }
            }

            if let coordinationError { throw coordinationError }
            if let writeError { throw writeError }
        }
    }

    private static func coordinate<T>(
        _ url: URL,
        relatedTo primaryURL: URL?,
        _ body: (NSFileCoordinator, RelatedItemPresenter?) throws -> T
    ) throws -> T {
        #if os(macOS)
        guard let primaryURL, primaryURL.standardizedFileURL != url.standardizedFileURL else {
            return try body(NSFileCoordinator(filePresenter: nil), nil)
        }

        let presenter = RelatedItemPresenter(relatedItem: url, of: primaryURL)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        return try body(NSFileCoordinator(filePresenter: presenter), presenter)
        #else
        // Related items are a macOS sandbox mechanism; `primaryPresentedItemURL` does
        // not exist elsewhere. On Apple TV the app reads what it downloaded into its
        // own container, which needs no permission from anyone.
        return try body(NSFileCoordinator(filePresenter: nil), nil)
        #endif
    }
}

#if os(macOS)
/// Names one file as belonging to another. The sandbox reads `primaryPresentedItemURL`
/// to decide whether the app has any business touching `presentedItemURL`.
final class RelatedItemPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let primaryPresentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue

    init(relatedItem: URL, of primaryItem: URL) {
        presentedItemURL = relatedItem
        primaryPresentedItemURL = primaryItem
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }
}
#else
/// Not a presenter anywhere but macOS; the type exists so the signatures match.
final class RelatedItemPresenter {}
#endif
