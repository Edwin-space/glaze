import Foundation

/// One place where subtitle files are read and written.
///
/// It exists because of a defect that is still open: under the App Sandbox, opening a
/// film grants access to that one file, and the `.srt` beside it — the entire premise
/// of sidecar subtitles — cannot be read. Every automatic subtitle load fails in the
/// configuration that ships. The unsandboxed Debug build never sees it.
///
/// The obvious remedy was *related items*, the mechanism macOS documents for exactly
/// this: declare the subtitle types with `NSIsRelatedItemType` in `Info.plist` and
/// reach the file through `NSFileCoordinator` with a presenter naming the video as its
/// primary item. That is what this type does, and **it is not sufficient** — measured
/// against a signed, sandboxed Release build, the read still fails, both for
/// `film.en.srt` and for `film.srt`, which matches the video's base name exactly.
///
/// What is known to work is a security-scoped bookmark for the containing folder,
/// asked for once through an open panel and kept. That is a change to what the viewer
/// sees, not just to plumbing, so it has not been made here yet. This type is where it
/// goes when it is: both the read and the write already funnel through it.
///
/// See `docs/19_engineering_guardrails.md` §8.
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
        guard let primaryURL, primaryURL.standardizedFileURL != url.standardizedFileURL else {
            return try body(NSFileCoordinator(filePresenter: nil), nil)
        }

        let presenter = RelatedItemPresenter(relatedItem: url, of: primaryURL)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        return try body(NSFileCoordinator(filePresenter: presenter), presenter)
    }
}

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
