import Foundation

/// What a Kodi-style `.nfo` beside a film says about it.
///
/// The Mac writes these; nothing read them back until now, which is why a shelf on the
/// television could only ever show a filename. Jellyfin, Emby and Kodi write the same
/// three shapes, so a library someone already curated with one of those is understood
/// here without asking them to redo it.
public struct MediaNFO: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case movie
        case tvShow
        case episode
    }

    public let kind: Kind
    public let title: String?
    public let originalTitle: String?
    public let sortTitle: String?
    /// The series an episode belongs to, which the episode file itself rarely says.
    public let showTitle: String?
    public let year: Int?
    public let plot: String?
    /// Out of 10, the scale every provider reports.
    public let rating: Double?
    public let genres: [String]
    public let studios: [String]
    public let season: Int?
    public let episode: Int?
    public let runtimeMinutes: Int?
    public let premiered: String?
    public let externalIDs: MediaExternalIDs

    public init(
        kind: Kind,
        title: String? = nil,
        originalTitle: String? = nil,
        sortTitle: String? = nil,
        showTitle: String? = nil,
        year: Int? = nil,
        plot: String? = nil,
        rating: Double? = nil,
        genres: [String] = [],
        studios: [String] = [],
        season: Int? = nil,
        episode: Int? = nil,
        runtimeMinutes: Int? = nil,
        premiered: String? = nil,
        externalIDs: MediaExternalIDs = MediaExternalIDs()
    ) {
        self.kind = kind
        self.title = title
        self.originalTitle = originalTitle
        self.sortTitle = sortTitle
        self.showTitle = showTitle
        self.year = year
        self.plot = plot
        self.rating = rating
        self.genres = genres
        self.studios = studios
        self.season = season
        self.episode = episode
        self.runtimeMinutes = runtimeMinutes
        self.premiered = premiered
        self.externalIDs = externalIDs
    }
}

public enum MediaNFOParser {
    /// - Returns: nil when the file is not an NFO this understands. A malformed one is
    ///   worth ignoring rather than surfacing: the film still plays.
    public static func parse(_ data: Data) -> MediaNFO? {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        // A truncated file still yields whatever elements closed before the break,
        // which is more useful than nothing.
        _ = parser.parse()
        return delegate.result
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        private var kind: MediaNFO.Kind?
        private var text = ""
        private var values: [String: String] = [:]
        private var genres: [String] = []
        private var studios: [String] = []
        private var uniqueIDs: [String: String] = [:]
        private var uniqueIDType: String?
        /// Depth inside the root, so `<actor><name>` cannot be mistaken for the film's
        /// own `<title>`.
        private var depth = 0

        var result: MediaNFO? {
            guard let kind else { return nil }
            let year = values["year"].flatMap(Int.init)
                ?? values["premiered"].flatMap { Int($0.prefix(4)) }
            return MediaNFO(
                kind: kind,
                title: values["title"],
                originalTitle: values["originaltitle"],
                sortTitle: values["sorttitle"],
                showTitle: values["showtitle"],
                year: year,
                plot: values["plot"] ?? values["outline"],
                rating: values["rating"].flatMap(Double.init),
                genres: genres,
                studios: studios,
                season: values["season"].flatMap(Int.init),
                episode: values["episode"].flatMap(Int.init),
                runtimeMinutes: values["runtime"].flatMap { Int($0.prefix(while: \.isNumber)) },
                premiered: values["premiered"],
                externalIDs: MediaExternalIDs(
                    imdbID: uniqueIDs["imdb"] ?? values["imdbid"] ?? values["id"],
                    tmdbID: uniqueIDs["tmdb"] ?? values["tmdbid"]
                )
            )
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            text = ""
            let name = elementName.lowercased()
            if kind == nil {
                switch name {
                case "movie": kind = .movie
                case "tvshow": kind = .tvShow
                case "episodedetails": kind = .episode
                default: break
                }
                if kind != nil { return }
            }
            depth += 1
            if name == "uniqueid" {
                uniqueIDType = attributeDict["type"]?.lowercased()
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(data: CDATABlock, encoding: .utf8) ?? ""
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            defer { text = "" }
            let name = elementName.lowercased()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            depth -= 1
            // Only the root's own children describe the film. Deeper ones belong to
            // an actor, a thumb or a fileinfo block.
            guard depth == 0, !value.isEmpty else { return }

            switch name {
            case "genre": genres.append(value)
            case "studio": studios.append(value)
            case "uniqueid":
                if let uniqueIDType { uniqueIDs[uniqueIDType] = value }
                uniqueIDType = nil
            default:
                // First one wins: Kodi files repeat `<rating>` inside `<ratings>`.
                if values[name] == nil { values[name] = value }
            }
        }
    }
}
