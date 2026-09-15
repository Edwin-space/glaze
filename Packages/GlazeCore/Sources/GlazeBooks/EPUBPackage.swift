import Foundation
import GlazeCore

/// One entry in a book's table of contents.
public struct EPUBChapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Path inside the archive, without the `#fragment`.
    public let path: String
    public let fragment: String?
    /// Nesting level, so a contents list can be indented.
    public let depth: Int

    public init(id: String, title: String, path: String, fragment: String? = nil, depth: Int = 0) {
        self.id = id
        self.title = title
        self.path = path
        self.fragment = fragment
        self.depth = depth
    }
}

/// What an EPUB says about itself.
public struct EPUBPackage: Equatable, Sendable {
    public let title: String?
    public let author: String?
    public let language: String?
    /// Reading order — paths inside the archive.
    public let spine: [String]
    public let coverPath: String?
    /// The contents list, when the book has one. Not every book does.
    public let chapters: [EPUBChapter]

    public init(
        title: String?,
        author: String?,
        language: String?,
        spine: [String],
        coverPath: String?,
        chapters: [EPUBChapter]
    ) {
        self.title = title
        self.author = author
        self.language = language
        self.spine = spine
        self.coverPath = coverPath
        self.chapters = chapters
    }
}

/// An `.epub`: XHTML in a zip, with a manifest saying what to read and in what order.
///
/// Unlike a comic, a book knows its own name. The file might be called
/// `dawkins_gene.epub` but the package says `이기적 유전자`, and that is what belongs
/// on a shelf.
public struct EPUBBook: Sendable {
    public enum Failure: Error, Equatable {
        case unreadable
        case notAnEPUB
        case noContent
    }

    public let archive: ZipArchive
    public let package: EPUBPackage

    public var url: URL { archive.url }

    public static func open(_ url: URL) throws -> EPUBBook {
        let archive: ZipArchive
        do {
            archive = try ZipArchive.open(url)
        } catch ZipArchive.Failure.unreadable {
            throw Failure.unreadable
        } catch {
            throw Failure.notAnEPUB
        }
        return EPUBBook(archive: archive, package: try read(archive))
    }

    /// Reads just the metadata, for the shelf. Cheap: the container and the package
    /// document together are a few kilobytes, whatever the book weighs.
    public static func readPackage(at url: URL) throws -> EPUBPackage {
        try open(url).package
    }

    /// Writes the whole book out to a folder.
    ///
    /// A reflowable book is XHTML with its own stylesheets, fonts and images, and a
    /// web view resolves those against the document's own folder. Serving them out of
    /// the zip one request at a time means a custom URL scheme and a lot of plumbing;
    /// unpacking once and pointing the web view at a real folder is the same result
    /// for a fraction of the code. Books are small — a novel is a megabyte or two.
    public func extract(to directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, entry) in archive.entries.enumerated() {
            guard !entry.name.hasSuffix("/") else { continue }
            // A member naming its way out of the folder would write anywhere on the
            // disk. Nothing legitimate in an epub does this.
            let resolved = Self.resolve(entry.name, relativeTo: "")
            guard !resolved.isEmpty, !resolved.hasPrefix("/") else { continue }

            let destination = directory.appendingPathComponent(resolved)
            guard destination.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path) else { continue }

            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = try? archive.data(at: index) else { continue }
            try data.write(to: destination, options: .atomic)
        }
    }

    // MARK: - Parsing

    static func read(_ archive: ZipArchive) throws -> EPUBPackage {
        // Every EPUB points at its package document from the same fixed path. That
        // is the one thing about the format that never moves.
        guard let containerData = try? archive.data(named: "META-INF/container.xml"),
              let opfPath = ContainerParser.rootFile(in: containerData)
        else { throw Failure.notAnEPUB }

        guard let opfData = try? archive.data(named: opfPath) else { throw Failure.notAnEPUB }

        let base = (opfPath as NSString).deletingLastPathComponent
        let opf = PackageParser.parse(opfData)
        guard !opf.spine.isEmpty else { throw Failure.noContent }

        let spinePaths = opf.spine.compactMap { id -> String? in
            guard let href = opf.manifest[id]?.href else { return nil }
            return resolve(href, relativeTo: base)
        }
        guard !spinePaths.isEmpty else { throw Failure.noContent }

        return EPUBPackage(
            title: opf.title,
            author: opf.author,
            language: opf.language,
            spine: spinePaths,
            coverPath: coverPath(from: opf, base: base, archive: archive),
            chapters: chapters(from: opf, base: base, archive: archive)
        )
    }

    /// EPUB 3 marks the cover in the manifest; EPUB 2 names it from a `meta` element.
    /// Both are common in the wild, so both are tried.
    private static func coverPath(from opf: OPF, base: String, archive: ZipArchive) -> String? {
        if let item = opf.manifest.values.first(where: { $0.properties.contains("cover-image") }) {
            return resolve(item.href, relativeTo: base)
        }
        if let id = opf.coverID, let item = opf.manifest[id] {
            return resolve(item.href, relativeTo: base)
        }
        // Some books have neither and simply put the cover first in the reading order.
        if let first = opf.spine.first, let item = opf.manifest[first],
           item.mediaType.hasPrefix("image/") {
            return resolve(item.href, relativeTo: base)
        }
        return nil
    }

    private static func chapters(from opf: OPF, base: String, archive: ZipArchive) -> [EPUBChapter] {
        if let navID = opf.manifest.first(where: { $0.value.properties.contains("nav") })?.key,
           let href = opf.manifest[navID]?.href {
            let path = resolve(href, relativeTo: base)
            if let data = try? archive.data(named: path) {
                let navBase = (path as NSString).deletingLastPathComponent
                let found = NavigationParser.parse(data, base: navBase, resolve: resolve)
                if !found.isEmpty { return found }
            }
        }

        // EPUB 2 keeps its contents in an NCX file the spine points at.
        if let tocID = opf.tocID, let href = opf.manifest[tocID]?.href {
            let path = resolve(href, relativeTo: base)
            if let data = try? archive.data(named: path) {
                let ncxBase = (path as NSString).deletingLastPathComponent
                return NCXParser.parse(data, base: ncxBase, resolve: resolve)
            }
        }
        return []
    }

    /// Hrefs in a package document are relative to the document, and routinely climb
    /// out of their folder with `../`. Left unresolved they name nothing in the zip.
    static func resolve(_ href: String, relativeTo base: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        let withoutFragment = decoded.split(separator: "#", maxSplits: 1).first.map(String.init) ?? decoded

        var components: [String] = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for part in withoutFragment.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    static func fragment(of href: String) -> String? {
        let decoded = href.removingPercentEncoding ?? href
        let parts = decoded.split(separator: "#", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[1])
    }
}

// MARK: - The package document

struct OPF {
    struct Item {
        let href: String
        let mediaType: String
        let properties: Set<String>
    }

    var title: String?
    var author: String?
    var language: String?
    var manifest: [String: Item] = [:]
    var spine: [String] = []
    var coverID: String?
    var tocID: String?
}

private final class ContainerParser: NSObject, XMLParserDelegate {
    private var found: String?

    static func rootFile(in data: Data) -> String? {
        let delegate = ContainerParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.found
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        guard found == nil, elementName.hasSuffix("rootfile") else { return }
        found = attributes["full-path"]?.removingPercentEncoding ?? attributes["full-path"]
    }
}

private final class PackageParser: NSObject, XMLParserDelegate {
    private var opf = OPF()
    private var text = ""
    private var element = ""

    static func parse(_ data: Data) -> OPF {
        let delegate = PackageParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        parser.parse()
        return delegate.opf
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        element = local(elementName)
        text = ""

        switch element {
        case "item":
            guard let id = attributes["id"], let href = attributes["href"] else { return }
            opf.manifest[id] = OPF.Item(
                href: href,
                mediaType: attributes["media-type"] ?? "",
                properties: Set((attributes["properties"] ?? "").split(separator: " ").map(String.init))
            )
        case "itemref":
            // `linear="no"` marks pages outside the reading order — adverts, errata.
            guard attributes["linear"] != "no", let id = attributes["idref"] else { return }
            opf.spine.append(id)
        case "spine":
            opf.tocID = attributes["toc"]
        case "meta":
            if attributes["name"] == "cover" { opf.coverID = attributes["content"] }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        guard !trimmed.isEmpty else { return }

        switch local(elementName) {
        case "title" where opf.title == nil: opf.title = trimmed
        case "creator" where opf.author == nil: opf.author = trimmed
        case "language" where opf.language == nil: opf.language = trimmed
        default: break
        }
    }

    /// `dc:title` and `title` are the same element to us.
    private func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

/// EPUB 3's contents list: an ordered list of links in an XHTML document.
private final class NavigationParser: NSObject, XMLParserDelegate {
    private var chapters: [EPUBChapter] = []
    private var base = ""
    private var resolve: ((String, String) -> String)!

    private var insideTOC = false
    private var depth = 0
    private var pendingHref: String?
    private var text = ""

    static func parse(
        _ data: Data,
        base: String,
        resolve: @escaping (String, String) -> String
    ) -> [EPUBChapter] {
        let delegate = NavigationParser()
        delegate.base = base
        delegate.resolve = resolve
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        parser.parse()
        return delegate.chapters
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        switch elementName.lowercased() {
        case "nav":
            // A book's navigation document also holds a page list and a landmarks
            // list; only the one typed `toc` is the contents.
            if attributes["epub:type"] == "toc" || attributes["type"] == "toc" { insideTOC = true }
        case "ol" where insideTOC:
            depth += 1
        case "a" where insideTOC:
            pendingHref = attributes["href"]
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard pendingHref != nil else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName.lowercased() {
        case "nav" where insideTOC:
            insideTOC = false
        case "ol" where insideTOC:
            depth = max(0, depth - 1)
        case "a" where insideTOC:
            defer { pendingHref = nil; text = "" }
            guard let href = pendingHref else { return }
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            chapters.append(
                EPUBChapter(
                    id: "\(chapters.count)",
                    title: title,
                    path: resolve(href, base),
                    fragment: EPUBBook.fragment(of: href),
                    depth: max(0, depth - 1)
                )
            )
        default:
            break
        }
    }
}

/// EPUB 2's contents list, in its own XML format.
private final class NCXParser: NSObject, XMLParserDelegate {
    private var chapters: [EPUBChapter] = []
    private var base = ""
    private var resolve: ((String, String) -> String)!

    private var depth = 0
    private var pendingTitle: String?
    private var text = ""
    private var insideLabel = false

    static func parse(
        _ data: Data,
        base: String,
        resolve: @escaping (String, String) -> String
    ) -> [EPUBChapter] {
        let delegate = NCXParser()
        delegate.base = base
        delegate.resolve = resolve
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        parser.parse()
        return delegate.chapters
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        switch elementName.lowercased() {
        case "navpoint":
            depth += 1
        case "navlabel":
            insideLabel = true
            text = ""
        case "content":
            guard let href = attributes["src"], let title = pendingTitle else { return }
            chapters.append(
                EPUBChapter(
                    id: "\(chapters.count)",
                    title: title,
                    path: resolve(href, base),
                    fragment: EPUBBook.fragment(of: href),
                    depth: max(0, depth - 1)
                )
            )
            pendingTitle = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideLabel else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName.lowercased() {
        case "navpoint":
            depth = max(0, depth - 1)
        case "navlabel":
            insideLabel = false
        case "text":
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { pendingTitle = trimmed }
        default:
            break
        }
    }
}
