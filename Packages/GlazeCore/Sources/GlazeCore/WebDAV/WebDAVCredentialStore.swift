import Foundation
import Security

/// Keeps NAS passwords in the keychain.
///
/// Not in `UserDefaults`, which is a plain file anything on the machine can read, and
/// not in the connection model, which gets encoded to preferences. A password for
/// someone's home server deserves the same handling as any other.
public struct WebDAVCredentialStore: Sendable {
    private let service: String

    public init(service: String = "com.edwin.glaze.webdav") {
        self.service = service
    }

    public func save(password: String, for connection: WebDAVConnection) {
        var query = baseQuery(for: connection)
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = Data(password.utf8)
        // Available after first unlock so a scheduled task can reach it, but never
        // synced to another device — this is one machine's access to one home server.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    public func password(for connection: WebDAVConnection) -> String? {
        var query = baseQuery(for: connection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    public func remove(for connection: WebDAVConnection) {
        SecItemDelete(baseQuery(for: connection) as CFDictionary)
    }

    /// Keyed on the connection's id rather than its URL: a viewer who corrects a
    /// hostname should not silently lose the password that went with it.
    private func baseQuery(for connection: WebDAVConnection) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.id
        ]
    }
}
