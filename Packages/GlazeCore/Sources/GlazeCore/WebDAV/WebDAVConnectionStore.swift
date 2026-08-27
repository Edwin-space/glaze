import Foundation
import Observation

/// Saved WebDAV locations shared by the Mac and Apple TV apps.
///
/// Connection metadata is small and non-sensitive, so it lives in `UserDefaults`.
/// Passwords never enter the encoded model and stay in the device keychain.
@MainActor
@Observable
public final class WebDAVConnectionStore {
    public private(set) var connections: [WebDAVConnection] = []

    private let storageKey: String
    private let credentials: WebDAVCredentialStore
    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard,
        credentials: WebDAVCredentialStore = WebDAVCredentialStore(),
        storageKey: String = "webdav.connections"
    ) {
        self.defaults = defaults
        self.credentials = credentials
        self.storageKey = storageKey
        connections = Self.load(from: defaults, key: storageKey)
    }

    /// Adds a connection or replaces the record with the same stable identifier.
    /// Passing `nil` preserves the password already stored for an edited record.
    public func save(_ connection: WebDAVConnection, password: String?) {
        if let password {
            credentials.save(password: password, for: connection)
        }

        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        connections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persist()
    }

    public func remove(_ connection: WebDAVConnection) {
        credentials.remove(for: connection)
        connections.removeAll { $0.id == connection.id }
        persist()
    }

    public func password(for connection: WebDAVConnection) -> String? {
        credentials.password(for: connection)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [WebDAVConnection] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WebDAVConnection].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
