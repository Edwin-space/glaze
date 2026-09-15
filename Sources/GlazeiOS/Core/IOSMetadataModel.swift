import Foundation
import GlazeCore
import Observation

/// Looking a film up again and putting the answer beside it.
///
/// A `.nfo` written by somebody else's scraper is often wrong, and until now the phone
/// had no way to say so: whatever the file claimed was the title, for good. Since the
/// answer is written as sidecar files next to the film — the same ones Kodi, Plex and
/// Glaze on the Mac already read — correcting it here corrects it everywhere that
/// folder is opened.
@MainActor
@Observable
final class IOSMetadataModel {
    enum Stage: Equatable {
        case idle
        case searching
        /// Candidates, best first. Empty means the search worked and found nothing,
        /// which is a normal answer and not a failure.
        case results([RankedMetadataMatch])
        case applying
        case done(String)
        case failed(String)
    }

    private(set) var stage: Stage = .idle

    /// What the file says about itself right now, before anything is changed.
    let current: MediaLibraryItem
    private let videoURL: URL

    init(item: MediaLibraryItem, videoURL: URL) {
        current = item
        self.videoURL = videoURL
    }

    /// - Parameter query: what to look for. Starts as the parsed title, but the whole
    ///   point of this screen is that the parse may be the thing that was wrong, so
    ///   the viewer can type over it.
    func search(_ query: String, year: Int?, apiKey: String, languageCode: String) async {
        let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            stage = .failed(L10n.string("ios.metadata.no_key"))
            return
        }

        stage = .searching
        let provider = TMDBMetadataProvider(apiKey: apiKey, session: NetworkSession.trusting)
        do {
            let found = try await provider.search(title: title, year: year, languageCode: languageCode)
            // Ranked against what the *filename* parsed to, not against what was typed:
            // the score is only a hint about which row to look at first, and the viewer
            // is the one deciding either way.
            stage = .results(MetadataMatchRanker.rank(found, against: current.parsed))
        } catch {
            stage = .failed(Self.message(for: error))
        }
    }

    /// Writes `<film>.nfo` and `<film>-poster.jpg` beside the film, replacing whatever
    /// was there. Nothing else on the device is touched; the folder is the record.
    func apply(_ match: MediaMetadataMatch) async {
        stage = .applying
        var poster: Data?
        if let posterURL = match.posterURL {
            poster = try? await NetworkSession.trusting.data(from: posterURL).0
        }

        do {
            let written = try MediaSidecarWriter().write(match, poster: poster, besideVideoAt: videoURL)
            stage = .done(
                String(format: L10n.string("ios.metadata.written_format"), match.title, written.count)
            )
        } catch {
            stage = .failed(L10n.string("ios.metadata.write_failed"))
        }
    }

    func startOver() { stage = .idle }

    private static func message(for error: Error) -> String {
        switch error {
        case MetadataProviderError.notConfigured: L10n.string("ios.metadata.no_key")
        case MetadataProviderError.rateLimited: L10n.string("ios.metadata.rate_limited")
        case MetadataProviderError.notFound: L10n.string("ios.metadata.not_found")
        case let MetadataProviderError.network(detail): detail
        default: (error as? URLError).map(ServerTrust.detail) ?? error.localizedDescription
        }
    }
}
