import Foundation

/// Finds a media server from an address someone typed, without multicast.
///
/// Automatic discovery shouts at `239.255.255.250`, and sending to a multicast
/// address on iOS, iPadOS and tvOS needs an entitlement Apple grants by application
/// (`docs/34`). Until that is granted, the search finds nothing on an Apple TV or an
/// iPhone however well the NAS is working — and the viewer is left thinking DLNA is
/// broken.
///
/// Typing the NAS's address needs none of that. Two ways are tried, in the order that
/// asks the server the least:
///
/// 1. a **unicast** SSDP search sent to that one host, which most servers answer
///    exactly as they answer the broadcast, and which reports the real description
///    address whatever port it is on;
/// 2. the addresses the common servers publish on, for those that ignore unicast.
public struct UPnPServerLocator: Sendable {
    public enum LocatorError: LocalizedError, Equatable {
        case noAddress
        case notFound

        public var errorDescription: String? {
            switch self {
            case .noAddress: L10n.string("network.manual.error.address")
            case .notFound: L10n.string("network.manual.error.not_found")
            }
        }
    }

    /// Where servers publish their description when they will not say so themselves.
    /// Synology's Media Server is minidlna, hence 8200 first.
    public static let commonDescriptionPaths: [(port: Int, path: String)] = [
        (8200, "/rootDesc.xml"),
        (9000, "/description.xml"),
        (32_469, "/DeviceDescription.xml"),
        (8096, "/dlna/description.xml"),
        (5_001, "/rootDesc.xml")
    ]

    private let session: URLSession
    private let discovery: UPnPMediaServerDiscoveryService

    public init(session: URLSession? = nil, responseWait: TimeInterval = 2) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            self.session = URLSession(configuration: configuration)
        }
        discovery = UPnPMediaServerDiscoveryService(responseWait: responseWait)
    }

    /// - Parameter typed: a host name, an address with a port, or the full address of
    ///   a device description XML.
    public func locate(_ typed: String) async throws -> NetworkMediaServer {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocatorError.noAddress }

        // A description someone pasted is the address, not a hint about one.
        if let direct = Self.describedURL(in: trimmed), let server = await server(at: direct) {
            return server
        }

        guard let (host, port) = Self.hostAndPort(in: trimmed) else { throw LocatorError.noAddress }

        if let answered = try? await discovery.askServer(host: host), let server = answered.first {
            return server
        }

        var candidates: [URL] = []
        if let port, let url = URL(string: "http://\(host):\(port)/rootDesc.xml") {
            candidates.append(url)
        }
        for candidate in Self.commonDescriptionPaths {
            if let url = URL(string: "http://\(host):\(candidate.port)\(candidate.path)") {
                candidates.append(url)
            }
        }

        for url in candidates {
            if let server = await server(at: url) { return server }
        }
        throw LocatorError.notFound
    }

    private func server(at url: URL) async -> NetworkMediaServer? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return UPnPDeviceDescriptionParser.parse(
            data: data,
            descriptionURL: url,
            fallbackID: url.absoluteString
        )
    }

    /// The typed text as a description URL, when that is what it is.
    static func describedURL(in typed: String) -> URL? {
        let withScheme = typed.contains("://") ? typed : "http://\(typed)"
        guard let url = URL(string: withScheme),
              url.host != nil,
              url.pathExtension.lowercased() == "xml" else { return nil }
        return url
    }

    /// The host and, when it was typed, the port — from anything a person might write.
    static func hostAndPort(in typed: String) -> (host: String, port: Int?)? {
        let withScheme = typed.contains("://") ? typed : "http://\(typed)"
        guard let components = URLComponents(string: withScheme),
              let host = components.host,
              !host.isEmpty else { return nil }
        return (host, components.port)
    }
}
