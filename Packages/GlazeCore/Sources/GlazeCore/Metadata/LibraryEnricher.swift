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
        /// Described already, but with no artwork beside it. The poster is filled in
        /// without touching the description someone else wrote.
        case posterAdded(String)
        case written([String])
        /// Ranked best first, for the viewer to choose from.
        case needsChoice([RankedMetadataMatch])
        case notFound
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
    /// Shows whose poster has already been written in this run.
    private var postersWritten: Set<String> = []

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
        // One lookup per show, not per episode. Twenty-four episodes of one series are
        // one question and one search, which is both faster and a better question.
        var seriesResults: [String: [RankedMetadataMatch]] = [:]

        for (index, item) in items.enumerated() {
            if Task.isCancelled { return outcomes }
            onProgress?(Progress(completed: index, total: items.count, title: item.displayTitle))

            if !overwriteExisting, item.metadata != nil {
                // A poster is not part of the description, and a library described
                // without one stays a wall of grey rectangles. Fill it in without
                // rewriting anything anyone curated.
                outcomes[item.id] = item.posterURL == nil
                    ? await posterOnlyOutcome(
                        for: item,
                        languageCode: languageCode,
                        alreadyCarried: postersWritten,
                        destination: destination
                    )
                    : .alreadyDescribed
                if case .posterAdded = outcomes[item.id], let key = posterKey(for: item) {
                    postersWritten.insert(key)
                }
                continue
            }

            if item.isEpisode, let showTitle = item.showTitle {
                let key = MediaLibraryIndex.groupingKey(for: showTitle)
                let ranked: [RankedMetadataMatch]
                if let cached = seriesResults[key] {
                    ranked = cached
                } else {
                    ranked = await rankedSeries(
                        for: showTitle,
                        alternates: item.parsed.alternateTitles,
                        languageCode: languageCode
                    )
                    seriesResults[key] = ranked
                }
                outcomes[item.id] = await episodeOutcome(
                    for: item,
                    showTitle: showTitle,
                    ranked: ranked,
                    carriesPoster: !postersWritten.contains(key),
                    destination: destination
                )
                if case .written = outcomes[item.id] { postersWritten.insert(key) }
                continue
            }

            outcomes[item.id] = await outcome(for: item, languageCode: languageCode, destination: destination)
        }

        onProgress?(Progress(completed: items.count, total: items.count, title: ""))
        return outcomes
    }

    /// Applies a series the viewer picked to every episode of that show.
    public func applySeries(
        _ match: MediaMetadataMatch,
        to episodes: [MediaLibraryItem],
        destination: @escaping DestinationProvider
    ) async -> [String: ItemOutcome] {
        var outcomes: [String: ItemOutcome] = [:]
        var poster: Data?
        if let posterURL = match.posterURL { poster = await loadPoster(posterURL) }

        for (index, episode) in episodes.enumerated() {
            outcomes[episode.id] = await writeEpisode(
                match,
                for: episode,
                showTitle: match.title.isEmpty ? (episode.showTitle ?? "") : match.title,
                // Only the first episode carries the show's poster.
                poster: index == 0 ? poster : nil,
                destination: destination
            )
        }
        return outcomes
    }

    /// Looks the film up again purely to fetch artwork for something already described.
    private func posterOnlyOutcome(
        for item: MediaLibraryItem,
        languageCode: String,
        alreadyCarried: Set<String>,
        destination: @escaping DestinationProvider
    ) async -> ItemOutcome {
        // One poster per show, as when describing it.
        if let key = posterKey(for: item), item.isEpisode, alreadyCarried.contains(key) {
            return .alreadyDescribed
        }

        let ranked: [RankedMetadataMatch]
        if item.isEpisode, let showTitle = item.metadata?.showTitle ?? item.showTitle {
            ranked = await rankedSeries(
                        for: showTitle,
                        alternates: item.parsed.alternateTitles,
                        languageCode: languageCode
                    )
        } else {
            let title = item.metadata?.title ?? item.parsed.title
            let parsed = ParsedMediaTitle(title: title, year: item.year)
            guard let matches = try? await provider.search(
                title: title, year: item.year, languageCode: languageCode
            ) else { return .alreadyDescribed }
            ranked = MetadataMatchRanker.rank(matches, against: parsed)
        }

        // Never asked about: the film is already described, and a question about
        // artwork alone is not worth a viewer's attention.
        guard MetadataMatchRanker.isUnambiguous(ranked),
              let poster = await loadPosterIfAny(ranked[0].match)
        else { return .alreadyDescribed }

        let name = "\(Self.baseName(of: item.sourceName))-poster.jpg"
        do {
            try await destination(item).write(poster, named: name)
            return .posterAdded(name)
        } catch {
            return .alreadyDescribed
        }
    }

    private func posterKey(for item: MediaLibraryItem) -> String? {
        guard item.isEpisode, let showTitle = item.metadata?.showTitle ?? item.showTitle else {
            return nil
        }
        return MediaLibraryIndex.groupingKey(for: showTitle)
    }

    private func rankedSeries(
        for showTitle: String,
        alternates: [String],
        languageCode: String
    ) async -> [RankedMetadataMatch] {
        let parsed = ParsedMediaTitle(title: showTitle)
        for candidate in [showTitle] + alternates {
            guard let matches = try? await provider.searchSeries(
                title: candidate,
                year: nil,
                languageCode: languageCode
            ), !matches.isEmpty else { continue }
            return MetadataMatchRanker.rank(matches, against: parsed)
        }
        return []
    }

    private func episodeOutcome(
        for item: MediaLibraryItem,
        showTitle: String,
        ranked: [RankedMetadataMatch],
        carriesPoster: Bool,
        destination: @escaping DestinationProvider
    ) async -> ItemOutcome {
        guard let best = ranked.first else { return .notFound }
        guard MetadataMatchRanker.isUnambiguous(ranked) else {
            return .needsChoice(Array(ranked.prefix(6)))
        }
        return await writeEpisode(
            best.match,
            for: item,
            // The looked-up name, not the one the release group typed. Writing 더 베어
            // rather than The.Bear is the reason for looking it up at all.
            showTitle: best.match.title.isEmpty ? showTitle : best.match.title,
            poster: carriesPoster ? await loadPosterIfAny(best.match) : nil,
            destination: destination
        )
    }

    private func loadPosterIfAny(_ match: MediaMetadataMatch) async -> Data? {
        guard let posterURL = match.posterURL else { return nil }
        return await loadPoster(posterURL)
    }

    private func writeEpisode(
        _ match: MediaMetadataMatch,
        for item: MediaLibraryItem,
        showTitle: String,
        poster: Data?,
        destination: @escaping DestinationProvider
    ) async -> ItemOutcome {
        do {
            let written = try await MediaSidecarWriter().writeEpisode(
                match,
                showTitle: showTitle,
                season: item.seasonNumber,
                episode: item.episodeNumber,
                episodeTitle: item.parsed.episodeTitle,
                poster: poster,
                baseName: Self.baseName(of: item.sourceName),
                to: destination(item)
            )
            return .written(written)
        } catch {
            return .failed(String(describing: error))
        }
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

        // The name as written first, then the halves of it. A Korean library names a
        // file in both scripts at once and neither index has an entry under the two
        // joined together.
        var matches: [MediaMetadataMatch] = []
        for candidate in [parsed.title] + parsed.alternateTitles {
            do {
                matches = try await provider.search(
                    title: candidate,
                    year: parsed.year,
                    languageCode: languageCode
                )
            } catch {
                return .failed(String(describing: error))
            }
            if !matches.isEmpty { break }
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
