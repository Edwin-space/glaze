import Foundation
import Observation

/// A direct entry point into a frequently used WebDAV folder.
///
/// Credentials remain attached to the referenced connection and never enter this
/// persisted value.
public struct WebDAVFavorite: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let connectionID: String
    public var name: String
    public var url: URL

    public init(connectionID: String, name: String, url: URL) {
        self.connectionID = connectionID
        self.name = name
        self.url = url
        self.id = "\(connectionID)#\(Self.key(for: url))"
    }

    fileprivate static func key(for url: URL) -> String {
        var value = url.standardized.absoluteString
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

@MainActor
@Observable
public final class WebDAVFavoriteStore {
    public private(set) var favorites: [WebDAVFavorite] = []

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "webdav.favorites"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        favorites = Self.load(from: defaults, key: storageKey)
    }

    public func contains(connectionID: String, url: URL) -> Bool {
        favorites.contains { $0.connectionID == connectionID && Self.sameFolder($0.url, url) }
    }

    public func toggle(connectionID: String, name: String, url: URL) {
        if let index = favorites.firstIndex(where: {
            $0.connectionID == connectionID && Self.sameFolder($0.url, url)
        }) {
            favorites.remove(at: index)
        } else {
            favorites.append(WebDAVFavorite(connectionID: connectionID, name: name, url: url))
        }
        favorites.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persist()
    }

    public func removeFavorites(forConnectionID connectionID: String) {
        let previousCount = favorites.count
        favorites.removeAll { $0.connectionID == connectionID }
        if favorites.count != previousCount { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [WebDAVFavorite] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WebDAVFavorite].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func sameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        WebDAVFavorite.key(for: lhs) == WebDAVFavorite.key(for: rhs)
    }
}
