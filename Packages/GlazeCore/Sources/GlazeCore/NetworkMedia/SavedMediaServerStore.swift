import Foundation
import Observation

/// A media server the viewer added by address.
///
/// Only the description address is kept. A server's control address and even its
/// friendly name can change when it restarts, so the description is read again on
/// each launch rather than trusting a copy taken weeks ago.
public struct SavedMediaServer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var descriptionURL: URL

    public init(id: String, name: String, descriptionURL: URL) {
        self.id = id
        self.name = name
        self.descriptionURL = descriptionURL
    }

    public init(_ server: NetworkMediaServer) {
        id = server.id
        name = server.friendlyName
        descriptionURL = server.descriptionURL
    }
}

/// The servers someone typed in, kept across launches.
///
/// Automatic discovery cannot run on an Apple TV or an iPhone without Apple's
/// multicast entitlement (`docs/34`), so a server added by hand has to stay added —
/// asking for the address again at every launch would make the feature not worth using.
@MainActor
@Observable
public final class SavedMediaServerStore {
    public private(set) var servers: [SavedMediaServer] = []

    private let store: UserDefaults
    private let key = "network.savedMediaServers"

    public init(store: UserDefaults = .standard) {
        self.store = store
        reload()
    }

    public func reload() {
        guard let data = store.data(forKey: key),
              let saved = try? JSONDecoder().decode([SavedMediaServer].self, from: data) else {
            servers = []
            return
        }
        servers = saved
    }

    public func save(_ server: SavedMediaServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        write()
    }

    public func remove(_ server: SavedMediaServer) {
        servers.removeAll { $0.id == server.id }
        write()
    }

    private func write() {
        store.set(try? JSONEncoder().encode(servers), forKey: key)
    }
}
