import Observation

@MainActor
@Observable
public final class NetworkMediaBrowserModel {
    public struct Level: Identifiable {
        public let id: String
        public let title: String
        public let nodes: [NetworkMediaNode]
    }

    public enum Phase: Equatable {
        case idle
        case discovering
        case browsing
    }

    private let discoveryService: any NetworkMediaServerDiscovering
    private let browser: any NetworkMediaServerBrowsing

    public var servers: [NetworkMediaServer] = []
    public var selectedServer: NetworkMediaServer?
    public var levels: [Level] = []
    public var homeNodes: [NetworkMediaNode] = []
    public var phase: Phase = .idle
    public var isHomeCatalogLoading = false
    public var errorMessage: String?

    public init(
        discoveryService: any NetworkMediaServerDiscovering = UPnPMediaServerDiscoveryService(),
        browser: any NetworkMediaServerBrowsing = UPnPContentDirectoryClient()
    ) {
        self.discoveryService = discoveryService
        self.browser = browser
    }

    public var currentNodes: [NetworkMediaNode] {
        levels.last?.nodes ?? []
    }

    public var navigationTitle: String {
        levels.last?.title ?? selectedServer?.friendlyName ?? L10n.string("network.browser.title")
    }

    public var canNavigateBack: Bool {
        selectedServer != nil
    }

    public func discoverIfNeeded() async {
        guard servers.isEmpty, phase == .idle else { return }
        await discover()
    }

    public func discover() async {
        phase = .discovering
        errorMessage = nil
        selectedServer = nil
        levels = []
        homeNodes = []
        do {
            servers = try await discoveryService.discoverServers()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        phase = .idle
    }

    public func select(_ server: NetworkMediaServer) async {
        if selectedServer?.id == server.id, !levels.isEmpty {
            if homeNodes.isEmpty, !isHomeCatalogLoading {
                await loadHomeCatalog(from: levels[0].nodes)
            }
            return
        }
        selectedServer = server
        levels = []
        homeNodes = []
        await browse(objectID: "0", title: server.friendlyName)
        guard errorMessage == nil, let root = levels.first else { return }
        await loadHomeCatalog(from: root.nodes)
    }

    @discardableResult
    public func restorePreferredServer(id: String) async -> Bool {
        if selectedServer?.id == id, !levels.isEmpty {
            if homeNodes.isEmpty, !isHomeCatalogLoading {
                await loadHomeCatalog(from: levels[0].nodes)
            }
            return errorMessage == nil
        }

        await discoverIfNeeded()
        guard let server = servers.first(where: { $0.id == id }) else { return false }
        await select(server)
        return errorMessage == nil
    }

    public func open(_ node: NetworkMediaNode) async {
        guard case .container = node.kind else { return }
        await browse(objectID: node.id, title: node.title)
    }

    public func navigateBack() {
        if levels.count > 1 {
            levels.removeLast()
        } else {
            levels = []
            selectedServer = nil
        }
        errorMessage = nil
    }

    public func navigate(to levelID: String) {
        guard let index = levels.firstIndex(where: { $0.id == levelID }) else { return }
        levels = Array(levels.prefix(through: index))
        errorMessage = nil
    }

    public func open(_ node: NetworkMediaNode, from levelID: String) async {
        navigate(to: levelID)
        await open(node)
    }

    public func retryCurrentLocation() async {
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
            let isServerRoot = levels.isEmpty && objectID == "0"
            let sourceNodes = if isServerRoot {
                try await browser.browseVideoRoots(server: selectedServer, objectID: objectID)
            } else {
                try await browser.browse(server: selectedServer, objectID: objectID)
            }
            let nodes = sourceNodes
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

    /// Builds a bounded, navigation-independent video catalog for Home.
    ///
    /// A UPnP server normally exposes a Videos container at its root, so rendering
    /// only `currentNodes` makes a connected library look empty. The catalog walks
    /// the video branches without moving the user's Library navigation position.
    private func loadHomeCatalog(from rootNodes: [NetworkMediaNode]) async {
        guard let selectedServer else { return }

        isHomeCatalogLoading = true
        defer { isHomeCatalogLoading = false }

        let maximumDepth = 4
        let maximumContainers = 64
        let maximumVideos = 300
        let browser = browser
        var catalog: [NetworkMediaNode] = []
        var seenVideos: Set<String> = []
        var visitedContainers: Set<String> = []

        func appendVideos(from nodes: [NetworkMediaNode]) {
            for node in nodes where catalog.count < maximumVideos {
                guard case .video = node.kind, seenVideos.insert(node.id).inserted else { continue }
                catalog.append(node)
            }
        }

        appendVideos(from: rootNodes)
        homeNodes = catalog

        var frontier = rootNodes.compactMap(Self.relevantContainerID)
        for _ in 0..<maximumDepth where !frontier.isEmpty && catalog.count < maximumVideos {
            let remainingBudget = maximumContainers - visitedContainers.count
            guard remainingBudget > 0 else { break }
            let batch = Array(frontier.prefix(remainingBudget)).filter {
                visitedContainers.insert($0).inserted
            }
            guard !batch.isEmpty else { break }

            let levels = await withTaskGroup(
                of: [NetworkMediaNode]?.self,
                returning: [[NetworkMediaNode]].self
            ) { group in
                for objectID in batch {
                    group.addTask {
                        try? await browser.browse(server: selectedServer, objectID: objectID)
                    }
                }
                var result: [[NetworkMediaNode]] = []
                for await nodes in group {
                    if let nodes { result.append(nodes) }
                }
                return result
            }

            for nodes in levels {
                appendVideos(from: nodes)
            }
            homeNodes = catalog
            frontier = levels.joined().compactMap(Self.relevantContainerID)
        }
    }

    private static func relevantContainerID(_ node: NetworkMediaNode) -> String? {
        guard case .container = node.kind, node.containerRelevance != .nonVideo else { return nil }
        return node.id
    }
}
