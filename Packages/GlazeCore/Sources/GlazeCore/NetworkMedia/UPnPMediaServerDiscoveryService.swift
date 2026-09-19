import Darwin
import Foundation

public actor UPnPMediaServerDiscoveryService: NetworkMediaServerDiscovering {
    public enum DiscoveryError: LocalizedError {
        case socketCreationFailed(Int32)
        case sendFailed(Int32)
        case receiveFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case .socketCreationFailed(let code):
                "Could not create the UPnP discovery socket (errno \(code))."
            case .sendFailed(let code):
                "Could not send the UPnP discovery request (errno \(code))."
            case .receiveFailed(let code):
                "Could not receive UPnP discovery responses (errno \(code))."
            }
        }
    }

    private let session: URLSession
    private let responseWait: TimeInterval

    public init(responseWait: TimeInterval = 2, session: URLSession? = nil) {
        self.responseWait = responseWait
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 10
            self.session = URLSession(configuration: configuration)
        }
    }

    public func discoverServers() async throws -> [NetworkMediaServer] {
        let responseWait = responseWait
        let packets = try await Task.detached(priority: .userInitiated) {
            try SSDPSocketSearch.search(responseWait: responseWait)
        }.value
        return try await servers(fromSSDP: packets)
    }

    /// Asks one host directly, rather than shouting at the whole network.
    ///
    /// The multicast search needs an entitlement Apple grants by application, which
    /// is why nothing is ever found on an Apple TV or an iPhone (`docs/34`). A
    /// unicast M-SEARCH to a NAS someone typed in needs no such permission, and most
    /// servers answer it exactly as they answer the broadcast.
    public func askServer(host: String, port: Int = 1900) async throws -> [NetworkMediaServer] {
        let responseWait = responseWait
        let packets = try await Task.detached(priority: .userInitiated) {
            try SSDPSocketSearch.search(responseWait: responseWait, host: host, port: UInt16(port))
        }.value
        return try await servers(fromSSDP: packets)
    }

    private func servers(fromSSDP packets: [Data]) async throws -> [NetworkMediaServer] {
        let responses = Dictionary(
            packets.compactMap(UPnPSSDP.parseResponse).map { ($0.uniqueServiceName, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values

        var servers: [NetworkMediaServer] = []
        for response in responses {
            do {
                let (data, urlResponse) = try await session.data(from: response.location)
                guard let httpResponse = urlResponse as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let server = UPnPDeviceDescriptionParser.parse(
                        data: data,
                        descriptionURL: response.location,
                        fallbackID: response.uniqueServiceName
                      ) else {
                    continue
                }
                servers.append(server)
            } catch {
                continue
            }
        }

        return servers.sorted {
            $0.friendlyName.localizedStandardCompare($1.friendlyName) == .orderedAscending
        }
    }
}

private enum SSDPSocketSearch {
    /// - Parameter host: where to send the search. The multicast group by default;
    ///   one server's own address when the network will not carry multicast.
    static func search(
        responseWait: TimeInterval,
        host: String = "239.255.255.250",
        port: UInt16 = 1900
    ) throws -> [Data] {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else {
            throw UPnPMediaServerDiscoveryService.DiscoveryError.socketCreationFailed(errno)
        }
        defer { close(socketDescriptor) }

        var timeout = timeval(
            tv_sec: Int(responseWait.rounded(.up)),
            tv_usec: 0
        )
        _ = withUnsafePointer(to: &timeout) { pointer in
            setsockopt(
                socketDescriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(port).bigEndian
        guard let address = Self.address(of: host) else {
            throw UPnPMediaServerDiscoveryService.DiscoveryError.sendFailed(errno)
        }
        destination.sin_addr = address

        let request = UPnPSSDP.mediaServerSearchRequest(maxWaitSeconds: Int(responseWait.rounded(.up)))
        let sentCount = request.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(
                        socketDescriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        address,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        guard sentCount == request.count else {
            throw UPnPMediaServerDiscoveryService.DiscoveryError.sendFailed(errno)
        }

        var packets: [Data] = []
        var buffer = [UInt8](repeating: 0, count: 65_535)
        while true {
            let receivedCount = recv(socketDescriptor, &buffer, buffer.count, 0)
            if receivedCount > 0 {
                packets.append(Data(buffer.prefix(receivedCount)))
                continue
            }

            if receivedCount == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
                break
            }
            if errno == EINTR {
                continue
            }
            throw UPnPMediaServerDiscoveryService.DiscoveryError.receiveFailed(errno)
        }

        return packets
    }

    /// People type `nas.local` as readily as `192.168.0.9`, and only one of those is
    /// something `inet_pton` understands.
    private static func address(of host: String) -> in_addr? {
        var parsed = in_addr()
        if inet_pton(AF_INET, host, &parsed) == 1 { return parsed }

        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_DGRAM,
            ai_protocol: IPPROTO_UDP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var results: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &results) == 0, let first = results else { return nil }
        defer { freeaddrinfo(results) }
        return first.pointee.ai_addr?.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            $0.pointee.sin_addr
        }
    }
}
