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

    /// The domains Synology's own DDNS hands out. Someone who turned DDNS on in DSM
    /// typed a host name and picked one of these from a menu; asking them to type
    /// `https://name.synology.me:5001` back afterwards is asking them to repeat work
    /// the NAS already did — and the port and scheme are where people get it wrong.
    public static let ddnsDomains = ["synology.me", "myds.me", "diskstation.me", "dscloud.me"]

    public static let defaultDDNSDomain = "synology.me"

    /// Builds the address from the host name someone chose in DSM and the domain it
    /// sits under. A DDNS name always has a certificate issued to it, so the result
    /// verifies normally — which is the whole reason for preferring it to an IP.
    ///
    /// - Returns: nil when there is no host name to work with.
    public static func compose(hostName: String, domain: String) -> URL? {
        let typed = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }

        let suffix = domain.trimmingCharacters(in: CharacterSet(charactersIn: " ./")).lowercased()
        // Someone who pasted a whole address, scheme and all, means it literally —
        // including plain HTTP to a box on their own network.
        guard !typed.contains("://"), !suffix.isEmpty else { return normalised(typed) }

        let host = typed.trimmingCharacters(in: CharacterSet(charactersIn: "./")).lowercased()
        guard !host.isEmpty else { return nil }
        // Pasting the whole name into the name box is the obvious mistake to make,
        // and `name.synology.me.synology.me` resolves to nothing.
        guard !host.hasSuffix(".\(suffix)") else { return normalised(host) }
        return normalised("\(host).\(suffix)")
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
