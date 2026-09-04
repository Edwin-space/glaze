import Foundation

/// Describes a whole library, one film at a time, and knows when to stop and ask.
///
/// Looking a film up by its filename is a guess. Most of the time it is a safe one —
/// an exact title with the right year is not really in doubt — but `Nosferatu` with no
/// year could be 1922 or 2024, and writing the wrong one beside someone's video is
/// worse than writing nothing. So this settles what it can and hands back the rest as
/// a question, ranked, for the viewer to answer.
public actor LibraryEnricher {
    public enum ItemOutcome: Equatable, Sendable {
        /// An `.nfo` is already there; a scan does not overwrite what someone curated.
        case alreadyDescribed
        case written([String])
        /// Ranked best first, for the viewer to choose from.
        case needsChoice([RankedMetadataMatch])
        case notFound
        /// An episode. The provider is being asked `search/movie`, so the candidates it
        /// returns for `The.Bear.S01E01` are films — offering those as an answer would
        /// invite writing a film's details onto an episode. Series lookup is a separate
        /// endpoint and not built yet; saying so is better than asking a bad question.
        case unsupportedKind
        case failed(String)
    }

    public struct Progress: Equatable, Sendable {
        public let completed: Int
        public let total: Int
        public let title: String
    }

    public typealias PosterLoader = @Sendable (URL) async -> Data?
    public typealias DestinationProvider = @Sendable (MediaLibraryItem) -> any SidecarDestination

    private let provider: any MetadataProviding
    private let loadPoster: PosterLoader

    public init(provider: any MetadataProviding, loadPoster: @escaping PosterLoader) {
        self.provider = provider
        self.loadPoster = loadPoster
    }

    /// - Parameter overwriteExisting: describe films that already have an `.nfo` too.
    ///   Off by default: a library someone curated in Kodi should survive a scan.
    public func enrich(
        _ items: [MediaLibraryItem],
        languageCode: String,
        destination: @escaping DestinationProvider,
        overwriteExisting: Bool = false,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async -> [String: ItemOutcome] {
        var outcomes: [String: ItemOutcome] = [:]

        for (index, item) in items.enumerated() {
            if Task.isCancelled { return outcomes }
            onProgress?(Progress(completed: index, total: items.count, title: item.displayTitle))

            guard overwriteExisting || item.metadata == nil else {
                outcomes[item.id] = .alreadyDescribed
                continue
            }
            guard !item.isEpisode else {
                outcomes[item.id] = .unsupportedKind
                continue
            }
            outcomes[item.id] = await outcome(for: item, languageCode: languageCode, destination: destination)
        }

        onProgress?(Progress(completed: items.count, total: items.count, title: ""))
        return outcomes
    }

    /// Writes the film the viewer picked from a `needsChoice` list.
    public func apply(
        _ match: MediaMetadataMatch,
        to item: MediaLibraryItem,
        destination: @escaping DestinationProvider
    ) async -> ItemOutcome {
        await write(match, for: item, destination: destination)
    }

    private func outcome(
        for item: MediaLibraryItem,
        languageCode: String,
        destination: @escaping DestinationProvider
    ) async -> ItemOutcome {
        let parsed = item.parsed
        guard !parsed.title.isEmpty else { return .notFound }

        let matches: [MediaMetadataMatch]
        do {
            matches = try await provider.search(
                title: parsed.title,
                year: parsed.year,
                languageCode: languageCode
            )
        } catch {
            return .failed(String(describing: error))
        }

        let ranked = MetadataMatchRanker.rank(matches, against: parsed)
        guard let best = ranked.first else { return .notFound }
        guard MetadataMatchRanker.isUnambiguous(ranked) else {
            // Capped: a viewer choosing between twenty near-identical rows is being
            // asked a worse question than one between five.
            return .needsChoice(Array(ranked.prefix(6)))
        }

        return await write(best.match, for: item, destination: destination)
    }

    private func write(
        _ match: MediaMetadataMatch,
        for item: MediaLibraryItem,
        destination: @escaping DestinationProvider
    ) async -> ItemOutcome {
        var poster: Data?
        if let posterURL = match.posterURL {
            poster = await loadPoster(posterURL)
        }

        do {
            let written = try await MediaSidecarWriter().write(
                match,
                poster: poster,
                baseName: Self.baseName(of: item.sourceName),
                to: destination(item)
            )
            return .written(written)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Sidecars take the film's own stem — `Film.2019.mkv` becomes `Film.2019.nfo` —
    /// which is what every media server looks for.
    static func baseName(of fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? fileName : stem
    }
}
