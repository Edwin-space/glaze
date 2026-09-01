import GlazeCore
import XCTest

@MainActor
final class NetworkMediaBrowserModelTests: XCTestCase {
    func testRestoresPreferredServerAndIndexesNestedVideosForHome() async throws {
        let server = makeServer()
        let movie = makeVideo(id: "movie-1", parentID: "movies")
        let discovery = DiscoveryStub(servers: [server])
        let browser = BrowserStub(nodes: [
            "0": [
                container(id: "video", parentID: "0", mediaClass: "object.container.videoContainer"),
                container(id: "photos", parentID: "0", mediaClass: "object.container.album.photoAlbum")
            ],
            "video": [container(id: "movies", parentID: "video")],
            "movies": [movie],
            "photos": [makeVideo(id: "photo-branch-video", parentID: "photos")]
        ])
        let model = NetworkMediaBrowserModel(discoveryService: discovery, browser: browser)

        let restored = await model.restorePreferredServer(id: server.id)

        XCTAssertTrue(restored)
        XCTAssertEqual(model.selectedServer, server)
        XCTAssertEqual(model.levels.count, 1, "Home indexing must not move Library navigation")
        XCTAssertEqual(model.homeNodes.map(\.id), [movie.id])
        let visited = await browser.requestedObjectIDs
        XCTAssertTrue(visited.contains("video"))
        XCTAssertTrue(visited.contains("movies"))
        XCTAssertFalse(visited.contains("photos"))
    }

    func testMissingPreferredServerLeavesTheBrowserDisconnected() async {
        let model = NetworkMediaBrowserModel(
            discoveryService: DiscoveryStub(servers: [makeServer()]),
            browser: BrowserStub(nodes: [:])
        )

        let restored = await model.restorePreferredServer(id: "missing")

        XCTAssertFalse(restored)
        XCTAssertNil(model.selectedServer)
        XCTAssertTrue(model.homeNodes.isEmpty)
    }

    private func makeServer() -> NetworkMediaServer {
        NetworkMediaServer(
            id: "server-1",
            friendlyName: "Living Room NAS",
            descriptionURL: URL(string: "http://nas.local/device.xml")!,
            contentDirectoryControlURL: URL(string: "http://nas.local/content")!
        )
    }

    private func container(
        id: String,
        parentID: String,
        mediaClass: String = "object.container.storageFolder"
    ) -> NetworkMediaNode {
        NetworkMediaNode(
            id: id,
            parentID: parentID,
            title: id,
            upnpClass: mediaClass,
            kind: .container(childCount: nil)
        )
    }

    private func makeVideo(id: String, parentID: String) -> NetworkMediaNode {
        let resource = NetworkMediaResource(
            serverID: "server-1",
            objectID: id,
            playbackURL: URL(string: "http://nas.local/video/\(id)")!
        )
        return NetworkMediaNode(
            id: id,
            parentID: parentID,
            title: "Movie",
            upnpClass: "object.item.videoItem.movie",
            kind: .video(resource)
        )
    }
}

private actor DiscoveryStub: NetworkMediaServerDiscovering {
    let servers: [NetworkMediaServer]

    init(servers: [NetworkMediaServer]) {
        self.servers = servers
    }

    func discoverServers() async throws -> [NetworkMediaServer] {
        servers
    }
}

private actor BrowserStub: NetworkMediaServerBrowsing {
    let nodes: [String: [NetworkMediaNode]]
    private(set) var requestedObjectIDs: [String] = []

    init(nodes: [String: [NetworkMediaNode]]) {
        self.nodes = nodes
    }

    func browse(server: NetworkMediaServer, objectID: String) async throws -> [NetworkMediaNode] {
        requestedObjectIDs.append(objectID)
        return nodes[objectID] ?? []
    }
}
