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
