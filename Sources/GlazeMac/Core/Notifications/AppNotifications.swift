import Foundation

extension Notification.Name {
    static let openVideoCommand = Notification.Name("Glaze.openVideoCommand")
    static let openMediaURL = Notification.Name("Glaze.openMediaURL")
}

/// Holds a file that was asked for before there was a window to play it in.
///
/// Opening a video at launch arrives before the player view exists, so the URL is
/// parked here and the view collects it when it appears. Anything delivered while a
/// window is already up is handled by the notification, and must be taken out of the
/// list at that moment — leaving it in meant every window that appeared afterwards
/// replayed the file the app was launched with.
@MainActor
enum PendingOpenMediaURLs {
    private static var urls: [URL] = []

    static func append(_ url: URL) {
        urls.append(url)
        NotificationCenter.default.post(name: .openMediaURL, object: url)
    }

    /// Takes the URL out of the list, if it is still there.
    static func consume(_ url: URL) {
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
    }

    static func consumeFirst() -> URL? {
        urls.isEmpty ? nil : urls.removeFirst()
    }
}
