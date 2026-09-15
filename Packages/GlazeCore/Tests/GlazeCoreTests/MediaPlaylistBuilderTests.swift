import Foundation
import Testing
@testable import GlazeCore

/// The Mac's playlist for a film opened from a folder.
@Suite(.serialized)
struct MediaPlaylistBuilderTests {
    private func folder(_ names: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("playlist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in names {
            FileManager.default.createFile(atPath: url.appendingPathComponent(name).path, contents: Data([0]))
        }
        return url
    }

    /// Opening episode two used to give "2, 1, 3, 4": next went back to episode one.
    @Test("Opening a film keeps the folder's order, so next and previous mean what they say")
    func keepsFolderOrder() throws {
        let dir = try folder(["Show.E03.mkv", "Show.E01.mkv", "Show.E04.mkv", "Show.E02.mkv"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let items = MediaPlaylistBuilder.playlist(for: dir.appendingPathComponent("Show.E02.mkv"))
        #expect(items.map(\.url.lastPathComponent) == ["Show.E01.mkv", "Show.E02.mkv", "Show.E03.mkv", "Show.E04.mkv"])

        let index = items.firstIndex { $0.url.lastPathComponent == "Show.E02.mkv" }
        #expect(index == 1)
    }

    @Test("Episode ten sorts after episode nine, the way a person numbers files")
    func numericOrder() throws {
        let dir = try folder(["E10.mkv", "E9.mkv", "E1.mkv"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let items = MediaPlaylistBuilder.playlist(for: dir.appendingPathComponent("E9.mkv"))
        #expect(items.map(\.url.lastPathComponent) == ["E1.mkv", "E9.mkv", "E10.mkv"])
    }
}
