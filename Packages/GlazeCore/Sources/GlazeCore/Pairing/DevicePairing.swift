import CryptoKit
import Foundation

/// Handing a server from a phone to a television.
///
/// Typing a NAS address, an account and a password on a remote control is the worst
/// job in the app, and using the phone as a keyboard is still typing. The phone has
/// already signed in — so the television shows a code, the phone reads it, and the
/// connection goes across.
///
/// The key that protects it is *in the code on the screen*, and is never sent
/// anywhere: it travels from the television's display to the phone's camera. A NAS
/// password should not cross even a home network in the clear.
public struct PairingPayload: Codable, Equatable, Sendable {
    public enum Server: Codable, Equatable, Sendable {
        case synology(baseURL: URL, account: String, password: String, libraryPath: String?)
        case webDAV(rootURL: URL, username: String, password: String, libraryPath: String?)
    }

    public let name: String
    public let server: Server

    public init(name: String, server: Server) {
        self.name = name
        self.server = server
    }
}

/// What the television puts on screen, and the phone reads back.
public struct PairingInvitation: Equatable, Sendable {
    public let host: String
    public let port: UInt16
    public let key: SymmetricKey

    public init(host: String, port: UInt16, key: SymmetricKey) {
        self.host = host
        self.port = port
        self.key = key
    }

    public static func makeKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// The text encoded into the QR code.
    ///
    /// Kept short: a long string makes a dense code, and a dense code on a television
    /// across a room is one a phone camera struggles to read.
    public var encoded: String {
        let raw = key.withUnsafeBytes { Data($0) }
        return "glaze-pair:\(host):\(port):\(Self.base64URL(raw))"
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "glaze-pair",
              let port = UInt16(parts[2]),
              let raw = Self.data(base64URL: String(parts[3])), raw.count == 32
        else { return nil }
        self.init(host: String(parts[1]), port: port, key: SymmetricKey(data: raw))
    }

    // Base64 with the two characters that would need escaping in a URL swapped out,
    // and the padding dropped.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64URL text: String) -> Data? {
        var padded = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        return Data(base64Encoded: padded)
    }
}

public enum PairingError: Error, Equatable, Sendable {
    case unreadableCode
    /// The message did not open with this key — a different television, or tampering.
    case wrongKey
    case malformedPayload
    case timedOut
    case transport(String)
}

public enum PairingCipher {
    public static func seal(_ payload: PairingPayload, with key: SymmetricKey) throws -> Data {
        let plain = try JSONEncoder().encode(payload)
        guard let sealed = try AES.GCM.seal(plain, using: key).combined else {
            throw PairingError.malformedPayload
        }
        return sealed
    }

    public static func open(_ data: Data, with key: SymmetricKey) throws -> PairingPayload {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: data)
        } catch {
            throw PairingError.malformedPayload
        }
        guard let plain = try? AES.GCM.open(box, using: key) else {
            throw PairingError.wrongKey
        }
        guard let payload = try? JSONDecoder().decode(PairingPayload.self, from: plain) else {
            throw PairingError.malformedPayload
        }
        return payload
    }
}
