import Foundation
import GlazeCore
import Observation

/// Finding out what a film is, and writing it down next to the film.
///
/// The filename is all there is to go on, which is why this leans on
/// `MediaTitleParser` — a search for
/// `Avatar.Fire.and.Ash.2025.2160p.HDR10Plus.DV.WEBRip.6CH.x265.HEVC-PSA` returns
/// nothing, and a search for "Avatar Fire and Ash" in 2025 returns the film.
@MainActor
@Observable
final class MetadataController {
    enum Phase: Equatable {
        case idle
        case searching
        /// More than one plausible film. The viewer picks, because a wrong match
        /// written beside the file is worse than no match.
        case choosing([MediaMetadataMatch])
        /// A candidate is never written immediately. The viewer confirms the poster,
        /// synopsis and editable title fields first.
        case reviewing(MediaMetadataMatch)
        case writing
        case written([URL])
        case needsFolderAccess(MediaMetadataMatch)
        case failed(String)
    }

    /// What is already recorded about this film, read from the `.nfo` beside it.
    ///
    /// The panel used to offer a blank TMDB search for every film, including the ones
    /// that already had a title, a synopsis and a poster sitting in the same folder —
    /// written by Glaze itself, or by whatever built the library. Someone opening
    /// "정보" to check a resolution was shown none of it and had no way to tell whether
    /// the film was identified at all.
    private(set) var known: MediaNFO?
    private(set) var knownPosterURL: URL?

    private(set) var phase: Phase = .idle
    var searchTitle = ""
    var searchYear = ""
    var draftTitle = ""
    var draftOriginalTitle = ""
    var draftYear = ""
    var draftOverview = ""

    private let sidecarWriter = MediaSidecarWriter()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func prepare(videoURL: URL) {
        let parsed = MediaTitleParser.parse(videoURL.deletingPathExtension().lastPathComponent)
        searchTitle = parsed.title
        searchYear = parsed.year.map(String.init) ?? ""
        clearDraft()
        phase = .idle
        readWhatIsAlreadyThere(besideVideoAt: videoURL)
    }

    /// Reads the sidecars the film already has. Silent when there are none: a film with
    /// no `.nfo` is the ordinary case, not a problem to report.
    func readWhatIsAlreadyThere(besideVideoAt videoURL: URL) {
        known = nil
        knownPosterURL = nil
        guard videoURL.isFileURL else { return }

        let folder = videoURL.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let companions = MediaCompanionFinder.find(videoName: videoURL.lastPathComponent, among: names)

        if let nfo = companions.nfo,
           let data = try? RelatedFileAccess.read(folder.appendingPathComponent(nfo), relatedTo: videoURL) {
            known = MediaNFOParser.parse(data)
        }
        knownPosterURL = companions.poster.map(folder.appendingPathComponent)
    }

    func reset() {
        clearDraft()
        phase = .idle
    }

    func lookUp(videoURL: URL, apiKey: String?) async {
        let title = searchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(searchYear.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !title.isEmpty else {
            phase = .failed(L10n.string("metadata.error.empty_search"))
            return
        }
        phase = .searching

        let provider = TMDBMetadataProvider(apiKey: apiKey, session: session)
        do {
            var matches = try await provider.search(
                title: title,
                year: year,
                languageCode: Locale.preferredLanguages.first ?? "en"
            )

            // A year in the filename is usually right, but not always, and a search
            // constrained to a wrong year finds nothing at all. Widen rather than fail.
            if matches.isEmpty, year != nil {
                matches = try await provider.search(
                    title: title,
                    year: nil,
                    languageCode: Locale.preferredLanguages.first ?? "en"
                )
            }

            guard !matches.isEmpty else {
                phase = .failed(L10n.string("metadata.error.not_found"))
                return
            }

            phase = .choosing(Array(matches.prefix(8)))
        } catch {
            phase = .failed(message(for: error))
        }
    }

    func select(_ match: MediaMetadataMatch) {
        draftTitle = match.title
        draftOriginalTitle = match.originalTitle ?? ""
        draftYear = match.year.map(String.init) ?? ""
        draftOverview = match.overview ?? ""
        phase = .reviewing(match)
    }

    func returnToResults(_ matches: [MediaMetadataMatch]) {
        phase = .choosing(matches)
    }

    func applySelected(_ original: MediaMetadataMatch, to videoURL: URL) async {
        let edited = MediaMetadataMatch(
            providerID: original.providerID,
            title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? original.title,
            originalTitle: draftOriginalTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            year: Int(draftYear.trimmingCharacters(in: .whitespacesAndNewlines)),
            overview: draftOverview.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            posterURL: original.posterURL,
            backdropURL: original.backdropURL,
            rating: original.rating,
            genres: original.genres,
            externalIDs: original.externalIDs
        )
        await apply(edited, to: videoURL)
    }

    func apply(_ match: MediaMetadataMatch, to videoURL: URL) async {
        phase = .writing

        // A missing poster is a plainer shelf, not a failed match, so the .nfo is
        // written either way.
        var poster: Data?
        if let posterURL = match.posterURL {
            poster = try? await session.data(from: posterURL).0
        }

        do {
            let written = try sidecarWriter.write(match, poster: poster, besideVideoAt: videoURL)
            phase = .written(written)
            // The panel above this one is showing what the film used to claim.
            readWhatIsAlreadyThere(besideVideoAt: videoURL)
        } catch {
            phase = .needsFolderAccess(match)
        }
    }

    func requestFolderAccessAndRetry(_ match: MediaMetadataMatch, videoURL: URL) async {
        guard MediaFolderAccess.requestAccess(toFolderOf: videoURL) else { return }
        await apply(match, to: videoURL)
    }

    private func clearDraft() {
        draftTitle = ""
        draftOriginalTitle = ""
        draftYear = ""
        draftOverview = ""
    }

    private func message(for error: Error) -> String {
        guard let providerError = error as? MetadataProviderError else {
            return L10n.string("metadata.error.network")
        }

        return switch providerError {
        case .notConfigured: L10n.string("metadata.error.no_key")
        case .notFound: L10n.string("metadata.error.not_found")
        case .rateLimited: L10n.string("metadata.error.rate_limited")
        case .network: L10n.string("metadata.error.network")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension MediaNFO {
    /// `S02E07` when the `.nfo` describes an episode. Nil for a film, so the summary
    /// line does not carry an empty slot for every film ever made.
    var episodeLabelForPanel: String? {
        guard let season, let episode else { return nil }
        return String(format: "S%02dE%02d", season, episode)
    }
}
