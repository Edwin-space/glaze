import Foundation
import Observation
import Security

/// A Synology someone has signed in to before.
public struct SynologyConnection: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public var name: String
    public var baseURL: URL
    public var account: String
    /// The shared folder to open, chosen once. `nil` means show the list of shares.
    public var libraryPath: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: URL,
        account: String,
        libraryPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.account = account
        self.libraryPath = libraryPath
    }
}

/// Keeps DSM passwords in the keychain, the same as the WebDAV ones.
public struct SynologyCredentialStore: Sendable {
    private let service: String

    public init(service: String = "com.edwin.glaze.synology") {
        self.service = service
    }

    public func save(password: String, for connection: SynologyConnection) {
        var query = baseQuery(for: connection)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    public func password(for connection: SynologyConnection) -> String? {
        var query = baseQuery(for: connection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func remove(for connection: SynologyConnection) {
        SecItemDelete(baseQuery(for: connection) as CFDictionary)
    }

    private func baseQuery(for connection: SynologyConnection) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.id,
        ]
    }
}

@MainActor
@Observable
public final class SynologyConnectionStore {
    public private(set) var connections: [SynologyConnection] = []

    private let storageKey: String
    private let credentials: SynologyCredentialStore
    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard,
        credentials: SynologyCredentialStore = SynologyCredentialStore(),
        storageKey: String = "synology.connections"
    ) {
        self.defaults = defaults
        self.credentials = credentials
        self.storageKey = storageKey
        connections = Self.load(from: defaults, key: storageKey)
    }

    public func reload() {
        connections = Self.load(from: defaults, key: storageKey)
    }

    /// Passing `nil` for the password keeps the one already stored.
    public func save(_ connection: SynologyConnection, password: String?) {
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

    public func remove(_ connection: SynologyConnection) {
        credentials.remove(for: connection)
        connections.removeAll { $0.id == connection.id }
        persist()
    }

    public func password(for connection: SynologyConnection) -> String? {
        credentials.password(for: connection)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [SynologyConnection] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([SynologyConnection].self, from: data)
        else { return [] }
        return stored
    }
}
