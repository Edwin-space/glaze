import Foundation
import GlazeCore
import Observation

/// Runs a whole-library pass: read the share, look each film up, write what is certain,
/// and collect what is not into a list of questions for the viewer.
///
/// The questions are the point. A scan that silently guessed would fill a library with
/// plausible wrong titles, and nobody would know which ones to distrust.
@MainActor
@Observable
final class LibraryScanController {
    /// Shared, and deliberately not owned by the screen that shows it.
    ///
    /// Describing a library takes minutes and writes to a NAS as it goes. Held as view
    /// state it was cancelled the moment anything re-created the window it sat in —
    /// which happened mid-run, halfway through a library, losing both the remaining
    /// work and the questions already gathered.
    static let shared = LibraryScanController()

    enum Phase: Equatable {
        case idle
        case scanning(foldersRead: Int)
        case describing(completed: Int, total: Int, title: String)
        case reviewing
        case finished
        case failed(String)
    }

    struct Question: Identifiable, Equatable {
        /// Usually one film. For a series it is every episode of that show, so the
        /// viewer answers once rather than twenty-four times.
        let items: [MediaLibraryItem]
        let candidates: [RankedMetadataMatch]

        var item: MediaLibraryItem { items[0] }
        var id: String { item.id }
        var isSeries: Bool { item.isEpisode }
        var subject: String { isSeries ? (item.showTitle ?? item.sourceName) : item.sourceName }
        var episodeCount: Int { items.count }
    }

    struct Summary: Equatable {
        var described = 0
        var alreadyDescribed = 0
        var notFound = 0
        var failed = 0
        var answered = 0
        var skipped = 0
        var postersAdded = 0
    }

    private(set) var phase: Phase = .idle
    private(set) var questions: [Question] = []
    private(set) var summary = Summary()
    private(set) var connectionName = ""

    private var task: Task<Void, Never>?
    private var root: URL?
    private var connection: WebDAVConnection?
    private var password: String?
    private let session = URLSession.shared

    var isRunning: Bool {
        switch phase {
        case .scanning, .describing: true
        default: false
        }
    }

    var currentQuestion: Question? { questions.first }

    /// - Parameter root: the folder to describe. The share's own root describes
    ///   everything; a folder inside it describes just that, which is how a large
    ///   library gets tried on a corner of itself first.
    func start(_ connection: WebDAVConnection, root: URL, password: String?, apiKey: String) {
        guard !apiKey.isEmpty else {
            phase = .failed(L10n.string("metadata.error.no_api_key"))
            return
        }

        cancel()
        self.connection = connection
        self.root = root
        self.password = password
        connectionName = root == connection.rootURL
            ? connection.name
            : "\(connection.name) › \(Self.folderName(of: root))"
        questions = []
        summary = Summary()
        phase = .scanning(foldersRead: 0)

        let credentials = password.map { (username: connection.username, password: $0) }
        let languageCode = Locale.preferredLanguages.first ?? "en"

        task = Task { [weak self] in
            guard let self else { return }
            let loader = WebDAVLibraryLoader()
            let library: MediaLibrary
            do {
                library = try await loader.load(root: root, credentials: credentials) { read in
                    Task { @MainActor [weak self] in self?.noteScanProgress(read) }
                }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.message(for: error))
                return
            }
            guard !Task.isCancelled else { return }

            let films = library.movies + library.series.flatMap(\.allEpisodes)
            guard !films.isEmpty else {
                phase = .finished
                return
            }

            phase = .describing(completed: 0, total: films.count, title: "")

            let enricher = LibraryEnricher(
                provider: TMDBMetadataProvider(apiKey: apiKey),
                loadPoster: { [session] url in
                    try? await session.data(from: url).0
                }
            )
            let outcomes = await enricher.enrich(
                films,
                languageCode: languageCode,
                destination: { item in
                    WebDAVSidecarDestination(besideVideoAt: item.playbackURL, credentials: credentials)
                },
                onProgress: { progress in
                    Task { @MainActor [weak self] in self?.noteDescribeProgress(progress) }
                }
            )

            guard !Task.isCancelled else { return }
            adopt(outcomes, films: films)
        }
    }

    /// Writes what the viewer picked — a film, or every episode of a show — then moves
    /// to the next question.
    func choose(_ candidate: RankedMetadataMatch) {
        guard let question = questions.first, let connection else { return }
        let credentials = password.map { (username: connection.username, password: $0) }
        questions.removeFirst()
        summary.answered += 1
        advanceIfDone()

        Task { [weak self, session] in
            let enricher = LibraryEnricher(
                provider: TMDBMetadataProvider(apiKey: nil),
                loadPoster: { url in try? await session.data(from: url).0 }
            )
            let destination: LibraryEnricher.DestinationProvider = { item in
                WebDAVSidecarDestination(besideVideoAt: item.playbackURL, credentials: credentials)
            }

            let outcomes: [String: LibraryEnricher.ItemOutcome] = if question.isSeries {
                await enricher.applySeries(candidate.match, to: question.items, destination: destination)
            } else {
                [question.item.id: await enricher.apply(
                    candidate.match, to: question.item, destination: destination
                )]
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                for outcome in outcomes.values {
                    if case .written = outcome { summary.described += 1 } else { summary.failed += 1 }
                }
            }
        }
    }

    /// Leaves a film undescribed. Better than a wrong title, and it can be asked again.
    func skipCurrentQuestion() {
        guard let question = questions.first else { return }
        questions.removeFirst()
        summary.skipped += question.items.count
        advanceIfDone()
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning { phase = .idle }
    }

    func reset() {
        cancel()
        questions = []
        summary = Summary()
        phase = .idle
    }

    private func advanceIfDone() {
        if questions.isEmpty { phase = .finished }
    }

    private func noteScanProgress(_ foldersRead: Int) {
        guard case .scanning = phase else { return }
        phase = .scanning(foldersRead: foldersRead)
    }

    private func noteDescribeProgress(_ progress: LibraryEnricher.Progress) {
        guard case .describing = phase else { return }
        phase = .describing(
            completed: progress.completed,
            total: progress.total,
            title: progress.title
        )
    }

    private func adopt(_ outcomes: [String: LibraryEnricher.ItemOutcome], films: [MediaLibraryItem]) {
        var pending: [Question] = []
        // Episodes of one show are one question. Keyed on the show so twenty-four
        // files do not become twenty-four identical questions.
        var seriesQuestions: [String: Int] = [:]

        // Walked in library order rather than dictionary order, so the questions arrive
        // in the order the shelf shows them.
        for film in films {
            switch outcomes[film.id] {
            case .written: summary.described += 1
            case .alreadyDescribed: summary.alreadyDescribed += 1
            case .posterAdded: summary.postersAdded += 1
            case .notFound: summary.notFound += 1
            case .failed: summary.failed += 1
            case .needsChoice(let candidates):
                if film.isEpisode, let showTitle = film.showTitle {
                    let key = MediaLibraryIndex.groupingKey(for: showTitle)
                    if let index = seriesQuestions[key] {
                        pending[index] = Question(
                            items: pending[index].items + [film],
                            candidates: pending[index].candidates
                        )
                    } else {
                        seriesQuestions[key] = pending.count
                        pending.append(Question(items: [film], candidates: candidates))
                    }
                } else {
                    pending.append(Question(items: [film], candidates: candidates))
                }
            case nil: break
            }
        }

        questions = pending
        phase = pending.isEmpty ? .finished : .reviewing
    }

    private static func folderName(of url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.host ?? "" : name
    }

    private static func message(for error: Error) -> String {
        switch error {
        case WebDAVError.unauthorized: L10n.string("webdav.error.unauthorized")
        case WebDAVError.notFound: L10n.string("webdav.error.not_found")
        case WebDAVError.notWebDAV: L10n.string("webdav.error.not_webdav")
        case WebDAVError.certificateMismatch: L10n.string("webdav.error.certificate")
        default: L10n.string("webdav.error.network")
        }
    }
}
