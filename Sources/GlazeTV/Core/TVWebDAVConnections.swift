import Foundation
import GlazeCore
import Observation

/// The NAS connections this Apple TV knows about.
///
/// Stored in `UserDefaults`, which on tvOS is the only place an app may keep anything
/// permanently — 500KB, and everything else is purgeable (`docs/23`). A handful of
/// connection records fits easily; the password is in the keychain, not here.
@MainActor
@Observable
final class TVWebDAVConnections {
    private static let key = "webdav.connections"

    private(set) var connections: [WebDAVConnection] = []

    private let credentials = WebDAVCredentialStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        connections = Self.load(from: defaults)
    }

    func add(_ connection: WebDAVConnection, password: String) {
        credentials.save(password: password, for: connection)
        connections.append(connection)
        persist()
    }

    func remove(_ connection: WebDAVConnection) {
        credentials.remove(for: connection)
        connections.removeAll { $0.id == connection.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func load(from defaults: UserDefaults) -> [WebDAVConnection] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WebDAVConnection].self, from: data) else {
            return []
        }
        return decoded
    }
}
