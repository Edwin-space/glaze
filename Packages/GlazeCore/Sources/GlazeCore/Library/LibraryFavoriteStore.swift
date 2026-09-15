import Foundation
import Observation

/// Something the viewer pinned — a single file, or the folder that holds a run of them.
///
/// Kept as a reference rather than a copy: the library is rebuilt from the folder on
/// every launch, so a favourite has to survive being re-read. It stores what the item
/// was called and where it came from, and the shelf resolves it against whatever the
/// current scan found. A favourite whose file has gone simply stops appearing, which
/// is better than a row that opens onto nothing.
public struct LibraryFavorite: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// One film.
        case film
        /// A show — a folder of episodes.
        case series
        /// One book or comic volume.
        case book
        /// A run of volumes under one name.
        case bookCollection
    }

    public let id: String
    /// Which library it belongs to, so a film on the NAS and one on the phone that
    /// happen to share a name stay apart.
    public let sourceKey: String
    public let kind: Kind
    public let itemID: String
    /// What to call it before the library has been read — the shelf shows favourites
    /// while a NAS is still being scanned.
    public var name: String
    public let addedAt: Date

    public init(sourceKey: String, kind: Kind, itemID: String, name: String, addedAt: Date = Date()) {
        self.sourceKey = sourceKey
        self.kind = kind
        self.itemID = itemID
        self.name = name
        self.addedAt = addedAt
        self.id = "\(sourceKey)|\(kind.rawValue)|\(itemID)"
    }
}

@MainActor
@Observable
public final class LibraryFavoriteStore {
    public private(set) var favorites: [LibraryFavorite] = []

    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard, storageKey: String = "library.favorites") {
        self.defaults = defaults
        self.storageKey = storageKey
        favorites = Self.load(from: defaults, key: storageKey)
    }

    public func contains(sourceKey: String, kind: LibraryFavorite.Kind, itemID: String) -> Bool {
        favorites.contains { $0.sourceKey == sourceKey && $0.kind == kind && $0.itemID == itemID }
    }

    /// - Returns: true when the item is now a favourite.
    @discardableResult
    public func toggle(
        sourceKey: String,
        kind: LibraryFavorite.Kind,
        itemID: String,
        name: String
    ) -> Bool {
        if let index = favorites.firstIndex(where: {
            $0.sourceKey == sourceKey && $0.kind == kind && $0.itemID == itemID
        }) {
            favorites.remove(at: index)
            persist()
            return false
        }

        favorites.append(
            LibraryFavorite(sourceKey: sourceKey, kind: kind, itemID: itemID, name: name)
        )
        sortNewestFirst()
        persist()
        return true
    }

    public func remove(_ favorite: LibraryFavorite) {
        let before = favorites.count
        favorites.removeAll { $0.id == favorite.id }
        if favorites.count != before { persist() }
    }

    /// Everything pinned in one library, newest first.
    public func favorites(inSource sourceKey: String) -> [LibraryFavorite] {
        favorites.filter { $0.sourceKey == sourceKey }
    }

    public func itemIDs(inSource sourceKey: String, kind: LibraryFavorite.Kind) -> [String] {
        favorites.filter { $0.sourceKey == sourceKey && $0.kind == kind }.map(\.itemID)
    }

    /// Drops everything pinned in a library the viewer has removed, so deleting a
    /// server does not leave its films listed under a star forever.
    public func removeFavorites(inSource sourceKey: String) {
        let before = favorites.count
        favorites.removeAll { $0.sourceKey == sourceKey }
        if favorites.count != before { persist() }
    }

    private func sortNewestFirst() {
        favorites.sort { $0.addedAt > $1.addedAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [LibraryFavorite] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LibraryFavorite].self, from: data)
        else { return [] }
        return decoded.sorted { $0.addedAt > $1.addedAt }
    }
}
