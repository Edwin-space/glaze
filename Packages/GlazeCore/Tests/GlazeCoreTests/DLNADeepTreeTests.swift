import Foundation
import Testing
@testable import GlazeCore

/// A media server shaped like a real Synology's: films live well below the root.
///
/// `0 → Video → By Folder → video (share) → Movies → Dune (2021) → Dune.mkv`
///
/// The Apple TV built its DLNA library by walking this tree to a fixed depth, and read
/// nothing at all when the films sat deeper than that — a connection that "worked"
/// and showed an empty library. It only looked right when a WebDAV server was added
/// as well, because that one filled the shelves by itself.
private struct DeepServer: NetworkMediaServerBrowsing {
    /// Levels of containers above the films.
    let depth: Int
    let filmsPerFolder: Int
    let foldersPerLevel: Int

    func browse(server: NetworkMediaServer, objectID: String) async throws -> [NetworkMediaNode] {
        let level = objectID == "0" ? 0 : objectID.split(separator: "/").count
        guard level < depth else {
            return (0..<filmsPerFolder).map { index in
                let id = "\(objectID)/film\(index)"
                return NetworkMediaNode(
                    id: id,
                    parentID: objectID,
                    title: "Film \(index).mkv",
                    upnpClass: "object.item.videoItem",
                    kind: .video(NetworkMediaResource(
                        serverID: server.id,
                        objectID: id,
                        playbackURL: URL(string: "http://nas/\(index)")!,
                        subtitleResources: []
                    ))
                )
            }
        }
        return (0..<foldersPerLevel).map { index in
            let id = objectID == "0" ? "c\(index)" : "\(objectID)/c\(index)"
            return NetworkMediaNode(
                id: id,
                parentID: objectID,
                title: "Folder \(index)",
                upnpClass: "object.container.storageFolder",
                kind: .container(childCount: nil)
            )
        }
    }
}

private struct NoDiscovery: NetworkMediaServerDiscovering {
    func discoverServers() async throws -> [NetworkMediaServer] { [] }
}

@MainActor
@Suite
struct DLNADeepTreeTests {
    private let server = NetworkMediaServer(
        id: "nas",
        friendlyName: "NAS",
        descriptionURL: URL(string: "http://nas/desc.xml")!,
        contentDirectoryControlURL: URL(string: "http://nas/ctl")!
    )

    /// Folder browsing asks for one level at a time, so depth costs nothing.
    @Test("Films six levels down are reached by browsing folder by folder")
    func folderBrowsingReachesThem() async throws {
        let deep = DeepServer(depth: 6, filmsPerFolder: 3, foldersPerLevel: 2)

        var path = "0"
        for _ in 0..<6 {
            let nodes = try await deep.browse(server: server, objectID: path)
            guard let next = nodes.first(where: { if case .container = $0.kind { true } else { false } }) else { break }
            path = next.id
        }
        let films = try await deep.browse(server: server, objectID: path)
        #expect(films.count == 3)
    }

    /// The catalogue behind the television's shelves has a budget, on purpose — reading
    /// a whole NAS on every connect is what was taken away everywhere else. This pins
    /// where that budget runs out, so nothing is ever built on the assumption that the
    /// catalogue will find a deep server's films. Folder browsing is the way in.
    @Test("The shelves' catalogue finds shallow films and none at Synology depth")
    func homeCatalogueHasALimit() async {
        let shallow = NetworkMediaBrowserModel(
            discoveryService: NoDiscovery(),
            browser: DeepServer(depth: 4, filmsPerFolder: 3, foldersPerLevel: 3)
        )
        await shallow.select(server)
        #expect(!shallow.homeNodes.isEmpty)

        let synologyDepth = NetworkMediaBrowserModel(
            discoveryService: NoDiscovery(),
            browser: DeepServer(depth: 6, filmsPerFolder: 3, foldersPerLevel: 3)
        )
        await synologyDepth.select(server)
        #expect(synologyDepth.homeNodes.isEmpty)
        // …and yet the server is selected and browsable. The Apple TV used to treat an
        // empty catalogue as "no server", which is the bug this file was written for.
        #expect(synologyDepth.selectedServer?.id == server.id)
    }
}
