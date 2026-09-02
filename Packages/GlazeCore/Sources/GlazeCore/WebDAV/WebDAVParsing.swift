import Foundation

/// Reads a WebDAV `PROPFIND` multistatus response.
///
/// Namespace prefixes are matched on the local name only. The spec lets a server pick
/// any prefix for the `DAV:` namespace and they do — Apache says `D:`, Synology says
/// `D:`, others say `d:` or `lp1:` — so keying on a prefix works against one server and
/// silently returns nothing against the next.
public enum WebDAVPropfindParser {
    public static func parse(_ data: Data, baseURL: URL) -> [WebDAVEntry] {
        let delegate = ParserDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return [] }
        return delegate.entries
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        private let baseURL: URL
        private(set) var entries: [WebDAVEntry] = []

        private var currentText = ""
        private var href: String?
        private var displayName: String?
        private var isCollection = false
        private var contentLength: Int64?
        private var contentType: String?
        private var lastModified: Date?
        private var insideResponse = false

        init(baseURL: URL) {
            self.baseURL = baseURL
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            currentText = ""
            switch localName(elementName) {
            case "response":
                insideResponse = true
                href = nil
                displayName = nil
                isCollection = false
                contentLength = nil
                contentType = nil
                lastModified = nil
            case "collection":
                // Presence is the answer; the element is empty.
                isCollection = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

            switch localName(elementName) {
            case "href" where insideResponse && href == nil:
                href = value
            case "displayname":
                displayName = value.isEmpty ? nil : value
            case "getcontentlength":
                contentLength = Int64(value)
            case "getcontenttype":
                contentType = value.isEmpty ? nil : value
            case "getlastmodified":
                lastModified = Self.parseHTTPDate(value)
            case "response":
                insideResponse = false
                appendEntry()
            default:
                break
            }

            currentText = ""
        }

        private func appendEntry() {
            guard let href, let url = resolve(href) else { return }

            // The folder being listed comes back as the first response. Listing it
            // inside itself would give every folder a phantom child of the same name.
            guard Self.folderKey(url) != Self.folderKey(baseURL) else { return }

            let name = displayName ?? url.lastPathComponent
            guard !name.isEmpty else { return }

            entries.append(
                WebDAVEntry(
                    url: url,
                    name: name,
                    isDirectory: isCollection,
                    byteCount: contentLength,
                    contentType: contentType,
                    lastModified: lastModified
                )
            )
        }

        /// `href` is sometimes a full URL and sometimes an absolute path; both are legal.
        private func resolve(_ href: String) -> URL? {
            if let absolute = URL(string: href), absolute.scheme != nil {
                return absolute
            }
            return URL(string: href, relativeTo: baseURL)?.absoluteURL
        }

        private func localName(_ elementName: String) -> String {
            (elementName.split(separator: ":").last.map(String.init) ?? elementName).lowercased()
        }

        private static func parseHTTPDate(_ text: String) -> Date? {
            guard !text.isEmpty else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return formatter.date(from: text)
        }

        /// Synology may echo the collection with a different trailing slash or URL
        /// spelling. Compare normalized origin and decoded path so it cannot appear
        /// as a child of itself.
        private static func folderKey(_ url: URL) -> String {
            let scheme = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""
            let port = url.port.map(String.init) ?? ""
            var path = url.standardized.path.removingPercentEncoding ?? url.standardized.path
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            return "\(scheme)://\(host):\(port)\(path)"
        }
    }
}
