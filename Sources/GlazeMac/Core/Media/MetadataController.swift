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
        case writing
        case written([URL])
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let sidecarWriter = MediaSidecarWriter()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func reset() {
        phase = .idle
    }

    func lookUp(videoURL: URL, apiKey: String?) async {
        let parsed = MediaTitleParser.parse(videoURL.deletingPathExtension().lastPathComponent)
        phase = .searching

        let provider = TMDBMetadataProvider(apiKey: apiKey, session: session)
        do {
            var matches = try await provider.search(
                title: parsed.title,
                year: parsed.year,
                languageCode: Locale.preferredLanguages.first ?? "en"
            )

            // A year in the filename is usually right, but not always, and a search
            // constrained to a wrong year finds nothing at all. Widen rather than fail.
            if matches.isEmpty, parsed.year != nil {
                matches = try await provider.search(
                    title: parsed.title,
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
            phase = .failed(L10n.string("metadata.error.write_failed"))
        }
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
