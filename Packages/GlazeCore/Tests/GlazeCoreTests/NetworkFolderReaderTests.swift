import Foundation
import Testing
@testable import GlazeCore

/// The sorting and classifying the three backends share, checked without a server.
///
/// What matters here is what a folder listing turns into: folders first, companions
/// hidden, and a film carrying the subtitles that were sitting beside it.
@Suite
struct NetworkFolderEntryTests {
    @Test("A film takes its title from the name, not the filename")
    func filmDisplayName() {
        let resource = NetworkMediaResource(
            serverID: "nas",
            objectID: "/x/Dune.2021.1080p.mkv",
            playbackURL: URL(string: "https://nas/x")!,
            subtitleResources: []
        )
        let entry = NetworkFolderEntry(
            path: "/x/Dune.2021.1080p.mkv",
            name: "Dune.2021.1080p.mkv",
            kind: .film(resource, MediaTitleParser.parse("Dune.2021.1080p.mkv"))
        )
        #expect(entry.displayName == "Dune")
        #expect(!entry.isFolder)
    }

    @Test("A folder is named as it is")
    func folderDisplayName() {
        let entry = NetworkFolderEntry(path: "/영화", name: "영화", kind: .folder)
        #expect(entry.displayName == "영화")
        #expect(entry.isFolder)
    }

    /// The reader hands anything it does not play up as a plain file with its
    /// extension, so the phone can recognise a comic without the television having to
    /// know what one is.
    @Test("Anything not played is passed up with its extension")
    func otherFiles() {
        let entry = NetworkFolderEntry(
            path: "/책/만화.cbz",
            name: "만화.cbz",
            kind: .file(extension: "cbz")
        )
        guard case .file(let ending) = entry.kind else {
            Issue.record("expected a plain file")
            return
        }
        #expect(ending == "cbz")
    }
}
