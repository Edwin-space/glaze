import Foundation

/// Reaches a file that sits next to a video the viewer opened.
///
/// Under the App Sandbox, opening a film grants access to that one file. The `.srt`
/// beside it — the entire premise of sidecar subtitles — is off limits, and the read
/// fails with a permission error that looks like a corrupt file. The unsandboxed Debug
/// build never sees this, so it only appears in the configuration that ships.
///
/// macOS calls these *related items*: files an app may reach because they belong to a
/// document already open. Two things are required, and neither works without the other:
/// the subtitle types are declared with `NSIsRelatedItemType` in `Info.plist`, and the
/// file is reached through `NSFileCoordinator` with a presenter naming the video as its
/// primary item. Registering that presenter is what hands over the sandbox extension.
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
