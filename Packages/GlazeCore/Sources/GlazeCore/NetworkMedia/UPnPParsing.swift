import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct SSDPDiscoveryResponse: Equatable, Sendable {
    public let location: URL
    public let uniqueServiceName: String
    public let searchTarget: String?
    public let server: String?
}

public enum UPnPSSDP {
    public static func mediaServerSearchRequest(maxWaitSeconds: Int = 2) -> Data {
        let boundedWait = min(max(maxWaitSeconds, 1), 5)
        let message = [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: \(boundedWait)",
            "ST: urn:schemas-upnp-org:device:MediaServer:1",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(message.utf8)
    }

    public static func parseResponse(_ data: Data) -> SSDPDiscoveryResponse? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.uppercased().contains("200 OK") == true else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        guard let locationValue = headers["location"],
              let location = URL(string: locationValue),
              let usn = headers["usn"], !usn.isEmpty else {
            return nil
        }

        return SSDPDiscoveryResponse(
            location: location,
            uniqueServiceName: usn,
            searchTarget: headers["st"],
            server: headers["server"]
        )
    }
}

public enum UPnPDeviceDescriptionParser {
    public static func parse(
        data: Data,
        descriptionURL: URL,
        fallbackID: String
    ) -> NetworkMediaServer? {
        let delegate = DeviceDescriptionXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(),
              let friendlyName = delegate.friendlyName,
              let controlURLValue = delegate.contentDirectoryControlURL else {
            return nil
        }

        let baseURL = delegate.urlBase.flatMap(URL.init(string:)) ?? descriptionURL
        guard let controlURL = URL(string: controlURLValue, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }

        return NetworkMediaServer(
            id: delegate.udn ?? fallbackID,
            friendlyName: friendlyName,
            descriptionURL: descriptionURL,
            contentDirectoryControlURL: controlURL
        )
    }
}

public enum DIDLLiteParser {
    public static func parse(data: Data, serverID: String) -> [NetworkMediaNode] {
        let delegate = DIDLXMLDelegate(serverID: serverID)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        return parser.parse() ? delegate.nodes : []
    }
}

public enum UPnPContentDirectoryResponseParser {
    public static func parse(data: Data, serverID: String) -> [NetworkMediaNode] {
        let delegate = SOAPResultXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(),
              let result = delegate.result,
              let resultData = result.data(using: .utf8) else {
            return []
        }

        return DIDLLiteParser.parse(data: resultData, serverID: serverID)
    }
}

private final class SOAPResultXMLDelegate: NSObject, XMLParserDelegate {
    var result: String?
    private var isReadingResult = false
    private var resultText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "Result" || elementName.hasSuffix(":Result") {
            isReadingResult = true
            resultText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingResult {
            resultText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Result" || elementName.hasSuffix(":Result") {
            result = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
            isReadingResult = false
        }
    }
}

private final class DeviceDescriptionXMLDelegate: NSObject, XMLParserDelegate {
    var friendlyName: String?
    var udn: String?
    var urlBase: String?
    var contentDirectoryControlURL: String?

    private var currentElement = ""
    private var currentText = ""
    private var currentServiceType: String?
    private var currentControlURL: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "service" {
            currentServiceType = nil
            currentControlURL = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "friendlyName": friendlyName = value
        case "UDN": udn = value
        case "URLBase": urlBase = value
        case "serviceType": currentServiceType = value
        case "controlURL": currentControlURL = value
        case "service":
            if currentServiceType?.contains(":service:ContentDirectory:") == true {
                contentDirectoryControlURL = currentControlURL
            }
        default: break
        }
        currentElement = ""
        currentText = ""
    }
}

private final class DIDLXMLDelegate: NSObject, XMLParserDelegate {
    struct PendingNode {
        let id: String
        let parentID: String
        let childCount: Int?
        let isContainer: Bool
        var title = ""
        var upnpClass: String?
        var resources: [PendingResource] = []
    }

    struct PendingResource {
        let protocolInfo: String?
        let byteCount: Int64?
        let duration: TimeInterval?
        var urlText = ""
    }

    let serverID: String
    var nodes: [NetworkMediaNode] = []
    private var pendingNode: PendingNode?
    private var pendingResource: PendingResource?
    private var currentText = ""

    init(serverID: String) {
        self.serverID = serverID
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch elementName {
        case "container", "item":
            guard let id = attributeDict["id"], let parentID = attributeDict["parentID"] else { return }
            pendingNode = PendingNode(
                id: id,
                parentID: parentID,
                childCount: attributeDict["childCount"].flatMap(Int.init),
                isContainer: elementName == "container"
            )
        case "res":
            pendingResource = PendingResource(
                protocolInfo: attributeDict["protocolInfo"],
                byteCount: attributeDict["size"].flatMap(Int64.init),
                duration: attributeDict["duration"].flatMap(Self.parseDuration)
            )
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title", "dc:title":
            pendingNode?.title = value
        case "class", "upnp:class":
            pendingNode?.upnpClass = value
        case "res":
            pendingResource?.urlText = value
            if let resource = pendingResource {
                pendingNode?.resources.append(resource)
            }
            pendingResource = nil
        case "container", "item":
            if let pendingNode {
                nodes.append(makeNode(pendingNode))
            }
            pendingNode = nil
        default:
            break
        }
        currentText = ""
    }

    private func makeNode(_ pending: PendingNode) -> NetworkMediaNode {
        if pending.isContainer {
            return NetworkMediaNode(
                id: pending.id,
                parentID: pending.parentID,
                title: pending.title,
                upnpClass: pending.upnpClass,
                kind: .container(childCount: pending.childCount)
            )
        }

        if let resource = pending.resources.first(where: { Self.mimeType(from: $0.protocolInfo)?.hasPrefix("video/") == true }),
           let url = URL(string: resource.urlText) {
            let networkResource = NetworkMediaResource(
                serverID: serverID,
                objectID: pending.id,
                playbackURL: url,
                mimeType: Self.mimeType(from: resource.protocolInfo),
                protocolInfo: resource.protocolInfo,
                byteCount: resource.byteCount,
                duration: resource.duration
            )
            return NetworkMediaNode(
                id: pending.id,
                parentID: pending.parentID,
                title: pending.title,
                upnpClass: pending.upnpClass,
                kind: .video(networkResource)
            )
        }

        return NetworkMediaNode(
            id: pending.id,
            parentID: pending.parentID,
            title: pending.title,
            upnpClass: pending.upnpClass,
            kind: .unsupported
        )
    }

    private static func mimeType(from protocolInfo: String?) -> String? {
        protocolInfo?.split(separator: ":", maxSplits: 3).dropFirst(2).first.map(String.init)
    }

    private static func parseDuration(_ value: String) -> TimeInterval? {
        let components = value.split(separator: ":").compactMap(Double.init)
        guard components.count == 3 else { return nil }
        return components[0] * 3_600 + components[1] * 60 + components[2]
    }
}
