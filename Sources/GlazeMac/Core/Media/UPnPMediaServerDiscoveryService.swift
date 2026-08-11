import Darwin
import Foundation
import GlazeCore

actor UPnPMediaServerDiscoveryService: NetworkMediaServerDiscovering {
    enum DiscoveryError: LocalizedError {
        case socketCreationFailed(Int32)
        case sendFailed(Int32)
        case receiveFailed(Int32)

        var errorDescription: String? {
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

    init(responseWait: TimeInterval = 2, session: URLSession? = nil) {
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

    func discoverServers() async throws -> [NetworkMediaServer] {
        let responseWait = responseWait
        let packets = try await Task.detached(priority: .userInitiated) {
            try SSDPSocketSearch.search(responseWait: responseWait)
        }.value

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
    static func search(responseWait: TimeInterval) throws -> [Data] {
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
        destination.sin_port = in_port_t(1900).bigEndian
        guard inet_pton(AF_INET, "239.255.255.250", &destination.sin_addr) == 1 else {
            throw UPnPMediaServerDiscoveryService.DiscoveryError.sendFailed(errno)
        }

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
}
