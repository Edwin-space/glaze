import Foundation

/// Turns what someone types into an address DSM answers on.
///
/// People type what they know — `203.0.113.10`, or `nas.example.com`, or the whole
/// thing with a port. DSM listens on 5000 for plain HTTP and 5001 for HTTPS, and
/// neither is what a bare host implies, so the gap has to be filled in somewhere.
/// Guessing here, once, beats every screen guessing differently.
public enum SynologyAddress {
    public static let httpPort = 5000
    public static let httpsPort = 5001

    /// - Returns: nil when there is no host to work with.
    public static func normalised(_ typed: String) -> URL? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A bare host has no scheme for URLComponents to find, so give it one first.
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let host = components.host, !host.isEmpty
        else { return nil }

        if components.scheme == nil { components.scheme = "https" }
        if components.port == nil {
            components.port = components.scheme == "http" ? httpPort : httpsPort
        }
        // DSM's API lives under /webapi; anything else someone pasted is not part of
        // the address of the box itself.
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Whether iOS will refuse this address for being plain HTTP to the open internet.
    ///
    /// App Transport Security allows cleartext on the local network only. A NAS
    /// published on a public address has to be reached over HTTPS, and saying so
    /// before the attempt is kinder than a connection error afterwards.
    public static func needsHTTPS(_ url: URL) -> Bool {
        guard url.scheme == "http", let host = url.host else { return false }
        return !isPrivate(host)
    }

    static func isPrivate(_ host: String) -> Bool {
        let lowered = host.lowercased()
        if lowered == "localhost" || lowered.hasSuffix(".local") { return true }

        let parts = lowered.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _): return true
        case (192, 168): return true
        case (172, 16...31): return true
        case (127, _): return true
        default: return false
        }
    }
}
