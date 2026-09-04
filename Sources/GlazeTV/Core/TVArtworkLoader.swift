import Foundation
import GlazeCore
import SwiftUI

/// Fetches the poster sitting beside a film and keeps it.
///
/// A shelf asks for the same poster every time it is drawn and the focus engine redraws
/// on every movement, so this has to answer from memory after the first time. tvOS gives
/// an app 500KB of persistent storage, so nothing is written to disk — the cache lives
/// for the session, which is exactly as long as the shelves do.
@Observable
@MainActor
final class TVArtworkLoader {
    private var images: [URL: Image] = [:]
    private var failed: Set<URL> = []
    private var inFlight: [URL: Task<Void, Never>] = [:]
    private let client = WebDAVClient()
    private var credentials: (username: String, password: String)?

    /// Posters live behind the same login as the films.
    func use(username: String, password: String?) {
        guard let password else {
            credentials = nil
            return
        }
        credentials = (username, password)
    }

    func image(for url: URL?) -> Image? {
        guard let url else { return nil }
        return images[url]
    }

    /// Called from the card as it appears. Repeat calls for a poster already loading or
    /// already known to be missing cost nothing.
    func loadIfNeeded(_ url: URL?) {
        guard let url, images[url] == nil, !failed.contains(url), inFlight[url] == nil else { return }

        inFlight[url] = Task { [weak self] in
            guard let self else { return }
            let credentials = credentials
            let client = client
            let loaded = await Task.detached(priority: .utility) { () -> Image? in
                guard let data = try? await client.fetch(
                    url,
                    credentials: credentials,
                    maximumBytes: 8 * 1_024 * 1_024
                ) else { return nil }
                #if canImport(UIKit)
                guard let image = UIImage(data: data) else { return nil }
                return Image(uiImage: image)
                #else
                return nil
                #endif
            }.value

            inFlight[url] = nil
            if let loaded {
                images[url] = loaded
            } else {
                // Remembered so a shelf does not re-request a poster that is not there
                // every time it scrolls back into view.
                failed.insert(url)
            }
        }
    }
}
