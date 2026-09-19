import Foundation
import GlazeCore
import Observation

/// Browsing a Synology by signing in to DSM, the way DS File does.
///
/// The Mac could already reach a NAS over WebDAV, but WebDAV is a package that has to
/// be installed and switched on in DSM first — the step that stops most people. The
/// phone has signed in to DSM directly since `docs/35`; this brings the Mac to the same
/// place, over the same `NetworkFolderReader` both platforms share, so a folder costs
/// one request rather than a crawl of the tree.
@MainActor
@Observable
final class MacSynologyBrowserModel {
    struct Level: Identifiable {
        let id: String
        let title: String
        /// DSM's own path for this folder; empty at the top, where the shares live.
        let path: String
        var entries: [NetworkFolderEntry]
    }

    enum Phase: Equatable {
        case idle
        case loading
        case ready
    }

    private(set) var levels: [Level] = []
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var connection: SynologyConnection?
    private(set) var session: SynologySession?

    private var reader: NetworkFolderReader?

    var canNavigateBack: Bool { levels.count > 1 }

    /// Signs in with the password kept in the keychain and lists the top folder.
    ///
    /// Sign-in lives here rather than in the sidebar because a DSM session lasts only
    /// as long as the app holds it: coming back to a saved NAS has to sign in again,
    /// and that is not something to make the viewer do by hand each time.
    func open(_ connection: SynologyConnection, password: String?) async {
        self.connection = connection
        levels = []
        errorMessage = nil
        phase = .loading

        guard let password, !password.isEmpty else {
            phase = .idle
            errorMessage = L10n.string("synology.error.no_saved_password")
            return
        }

        do {
            let session = try await SynologyClient().logIn(
                to: connection.baseURL,
                account: connection.account,
                password: password
            )
            self.session = session
            let root = connection.libraryPath ?? ""
            reader = NetworkFolderReader(
                serverName: connection.name,
                backend: .synology(session: session),
                rootPath: root
            )
            await push(path: root, title: connection.name)
        } catch {
            phase = .idle
            session = nil
            reader = nil
            errorMessage = message(for: error)
        }
    }

    func open(_ entry: NetworkFolderEntry) async {
        guard entry.isFolder else { return }
        await push(path: entry.path, title: entry.name)
    }

    func navigate(to levelID: String) {
        guard let index = levels.firstIndex(where: { $0.id == levelID }) else { return }
        levels.removeSubrange((index + 1)...)
    }

    func navigateBack() {
        guard canNavigateBack else { return }
        levels.removeLast()
    }

    func reloadCurrent() async {
        guard let current = levels.last else { return }
        levels.removeLast()
        await push(path: current.path, title: current.title)
    }

    func disconnect() {
        if let session {
            let client = SynologyClient()
            Task { await client.logOut(session) }
        }
        session = nil
        reader = nil
        connection = nil
        levels = []
        phase = .idle
        errorMessage = nil
    }

    /// What to play, with the session's credentials already in the URL.
    func resource(for entry: NetworkFolderEntry) -> NetworkMediaResource? {
        guard case .film(let resource, _) = entry.kind else { return nil }
        return resource
    }

    private func push(path: String, title: String) async {
        guard let reader else { return }
        phase = .loading
        errorMessage = nil
        do {
            let entries = try await reader.read(path)
            levels.append(Level(id: path.isEmpty ? "/" : path, title: title, path: path, entries: entries))
            phase = .ready
        } catch {
            phase = levels.isEmpty ? .idle : .ready
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        SynologyErrorMessage.text(for: error)
    }
}
