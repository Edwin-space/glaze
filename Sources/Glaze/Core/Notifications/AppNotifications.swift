import Foundation

extension Notification.Name {
    static let openVideoCommand = Notification.Name("Glaze.openVideoCommand")
    static let openMediaURL = Notification.Name("Glaze.openMediaURL")
}

@MainActor
enum PendingOpenMediaURLs {
    private static var urls: [URL] = []

    static func append(_ url: URL) {
        urls.append(url)
        NotificationCenter.default.post(name: .openMediaURL, object: url)
    }

    static func consumeFirst() -> URL? {
        if urls.isEmpty {
            return nil
        }

        return urls.removeFirst()
    }

    static func contains(_ url: URL) -> Bool {
        urls.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }
}
