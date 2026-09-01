import Foundation

public actor UPnPContentDirectoryClient: NetworkMediaServerBrowsing {
    public enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "The media server returned an invalid response."
            case .httpStatus(let status):
                "The media server returned HTTP status \(status)."
            }
        }
    }

    private let session: URLSession
    private var browseCache: [String: [NetworkMediaNode]] = [:]

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: configuration)
        }
    }

    public func browse(server: NetworkMediaServer, objectID: String) async throws -> [NetworkMediaNode] {
        try await loadNodes(server: server, objectID: objectID)
    }

    /// Returns a media-server root suitable for a video player rather than a generic
    /// UPnP browser. Synology, for example, labels both Photos and Videos as the same
    /// `storageFolder` class, so ambiguous roots are inspected until a playable video
    /// is found. This keeps photo and music branches out without relying on English or
    /// Korean folder names.
    public func browseVideoRoots(
        server: NetworkMediaServer,
        objectID: String = "0"
    ) async throws -> [NetworkMediaNode] {
        let nodes = try await loadNodes(server: server, objectID: objectID)
        let ambiguousContainers = nodes.filter {
            guard case .container = $0.kind else { return false }
            return $0.containerRelevance == .unknown
        }
        let playableAmbiguousIDs = await withTaskGroup(
            of: (String, Bool).self,
            returning: Set<String>.self
        ) { group in
            for node in ambiguousContainers {
                group.addTask {
                    let containsVideo = (try? await self.containsPlayableVideo(
                        server: server,
                        rootID: node.id
                    )) == true
                    return (node.id, containsVideo)
                }
            }

            var result: Set<String> = []
            for await (id, containsVideo) in group {
                if containsVideo { result.insert(id) }
            }
            return result
        }

        return nodes.filter { node in
            switch node.kind {
            case .video:
                return true
            case .unsupported:
                return false
            case .container:
                switch node.containerRelevance {
                case .video:
                    return true
                case .nonVideo:
                    return false
                case .unknown:
                    return playableAmbiguousIDs.contains(node.id)
                }
            }
        }
    }

    private func loadNodes(server: NetworkMediaServer, objectID: String) async throws -> [NetworkMediaNode] {
        let cacheKey = "\(server.id)#\(objectID)"
        if let cached = browseCache[cacheKey] {
            return cached
        }

        var request = URLRequest(url: server.contentDirectoryControlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"",
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = Self.browseEnvelope(objectID: objectID)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode)
        }

        let nodes = UPnPContentDirectoryResponseParser.parse(data: data, serverID: server.id)
        browseCache[cacheKey] = nodes
        return nodes
    }

    private func containsPlayableVideo(
        server: NetworkMediaServer,
        rootID: String
    ) async throws -> Bool {
        let maximumDepth = 3
        let maximumContainers = 48
        var frontier = [rootID]
        var visited: Set<String> = []
        var inspected = 0

        for depth in 0...maximumDepth where !frontier.isEmpty && inspected < maximumContainers {
            let remainingBudget = maximumContainers - inspected
            let batch = Array(frontier.prefix(remainingBudget)).filter {
                visited.insert($0).inserted
            }
            inspected += batch.count
            guard !batch.isEmpty else { break }

            let levels = try await withThrowingTaskGroup(
                of: [NetworkMediaNode].self,
                returning: [[NetworkMediaNode]].self
            ) { group in
                for id in batch {
                    group.addTask {
                        try await self.loadNodes(server: server, objectID: id)
                    }
                }
                var result: [[NetworkMediaNode]] = []
                for try await nodes in group { result.append(nodes) }
                return result
            }

            if levels.joined().contains(where: { node in
                if case .video = node.kind { return true }
                return node.containerRelevance == .video
            }) {
                return true
            }

            guard depth < maximumDepth else { break }
            frontier = levels.joined().compactMap { child in
                guard case .container = child.kind else { return nil }
                switch child.containerRelevance {
                case .video: return child.id
                case .nonVideo: return nil
                case .unknown: return child.id
                }
            }
        }

        return false
    }

    private static func browseEnvelope(objectID: String) -> Data {
        let escapedObjectID = objectID
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")

        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
              <ObjectID>\(escapedObjectID)</ObjectID>
              <BrowseFlag>BrowseDirectChildren</BrowseFlag>
              <Filter>*</Filter>
              <StartingIndex>0</StartingIndex>
              <RequestedCount>0</RequestedCount>
              <SortCriteria></SortCriteria>
            </u:Browse>
          </s:Body>
        </s:Envelope>
        """
        return Data(body.utf8)
    }
}
