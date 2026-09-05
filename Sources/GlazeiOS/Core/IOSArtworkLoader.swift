import Foundation
import GlazeCore
import SwiftUI
import UIKit

/// Fetches the poster sitting beside a film and keeps it for the session.
///
/// A list redraws constantly while it scrolls, so this has to answer from memory after
/// the first time. Nothing is written to disk: the poster is already on the NAS, and a
/// phone's storage is not the place to keep a second copy.
@Observable
@MainActor
final class IOSArtworkLoader {
    private var images: [URL: Image] = [:]
    private var failed: Set<URL> = []
    private var inFlight: [URL: Task<Void, Never>] = [:]
    private let client = WebDAVClient()
    private var credentials: (username: String, password: String)?

    /// Posters live behind the same login as the films.
    func use(username: String, password: String?) {
        guard let password, !username.isEmpty else {
            credentials = nil
            return
        }
        credentials = (username, password)
    }

    func image(for url: URL?) -> Image? {
        guard let url else { return nil }
        return images[url]
    }

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
                ), let image = UIImage(data: data) else { return nil }
                return Image(uiImage: image)
            }.value

            inFlight[url] = nil
            if let loaded {
                images[url] = loaded
            } else {
                // Remembered, so a list does not ask again every time it scrolls back.
                failed.insert(url)
            }
        }
    }
}
