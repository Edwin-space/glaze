import GlazeCore
import Observation

@MainActor
@Observable
final class NetworkMediaBrowserModel {
    struct Level: Identifiable {
        let id: String
        let title: String
        let nodes: [NetworkMediaNode]
    }

    enum Phase: Equatable {
        case idle
        case discovering
        case browsing
    }

    private let discoveryService: UPnPMediaServerDiscoveryService
    private let browser: UPnPContentDirectoryClient

    var servers: [NetworkMediaServer] = []
    var selectedServer: NetworkMediaServer?
    var levels: [Level] = []
    var phase: Phase = .idle
    var errorMessage: String?

    init(
        discoveryService: UPnPMediaServerDiscoveryService = UPnPMediaServerDiscoveryService(),
        browser: UPnPContentDirectoryClient = UPnPContentDirectoryClient()
    ) {
        self.discoveryService = discoveryService
        self.browser = browser
    }

    var currentNodes: [NetworkMediaNode] {
        levels.last?.nodes ?? []
    }

    var navigationTitle: String {
        levels.last?.title ?? selectedServer?.friendlyName ?? L10n.string("network.browser.title")
    }

    var canNavigateBack: Bool {
        selectedServer != nil
    }

    func discoverIfNeeded() async {
        guard servers.isEmpty, phase == .idle else { return }
        await discover()
    }

    func discover() async {
        phase = .discovering
        errorMessage = nil
        selectedServer = nil
        levels = []
        do {
            servers = try await discoveryService.discoverServers()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        phase = .idle
    }

    func select(_ server: NetworkMediaServer) async {
        selectedServer = server
        levels = []
        await browse(objectID: "0", title: server.friendlyName)
    }

    func open(_ node: NetworkMediaNode) async {
        guard case .container = node.kind else { return }
        await browse(objectID: node.id, title: node.title)
    }

    func navigateBack() {
        if levels.count > 1 {
            levels.removeLast()
        } else {
            levels = []
            selectedServer = nil
        }
        errorMessage = nil
    }

    func retryCurrentLocation() async {
        guard let selectedServer else {
            await discover()
            return
        }
        let target = levels.last.map { ($0.id, $0.title) } ?? ("0", selectedServer.friendlyName)
        if !levels.isEmpty {
            levels.removeLast()
        }
        await browse(objectID: target.0, title: target.1)
    }

    private func browse(objectID: String, title: String) async {
        guard let selectedServer else { return }
        phase = .browsing
        errorMessage = nil
        do {
            let nodes = try await browser.browse(server: selectedServer, objectID: objectID)
                .filter {
                    switch $0.kind {
                    case .container, .video: true
                    case .unsupported: false
                    }
                }
            levels.append(Level(id: objectID, title: title, nodes: nodes))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        phase = .idle
    }
}
