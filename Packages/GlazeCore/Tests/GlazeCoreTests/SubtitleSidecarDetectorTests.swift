import Foundation
import Testing
@testable import GlazeCore

struct SubtitleSidecarDetectorTests {
    private func makeFolder(_ names: [String]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glaze-detect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            FileManager.default.createFile(
                atPath: directory.appendingPathComponent(name).path,
                contents: Data()
            )
        }
        return directory
    }

    private func detected(_ names: [String], for video: String) throws -> [String] {
        let directory = try makeFolder(names)
        defer { try? FileManager.default.removeItem(at: directory) }
        return SubtitleSidecarDetector
            .detect(for: directory.appendingPathComponent(video))
            .map(\.displayName)
    }

    @Test func findsASubtitleNamedExactlyLikeTheVideo() throws {
        #expect(try detected(["film.mkv", "film.srt"], for: "film.mkv") == ["film.srt"])
    }

    @Test func findsLanguageTaggedSubtitles() throws {
        let found = try detected(["film.mkv", "film.en.srt", "film.ko.srt"], for: "film.mkv")
        #expect(found.sorted() == ["film.en.srt", "film.ko.srt"])
    }

    /// The app saves translations as `film.original.ko.srt`. The old fixed candidate
    /// list had no entry for it, so a translation the viewer had waited minutes for
    /// vanished the next time they opened the film.
    @Test func findsTheAppsOwnTranslationOutput() throws {
        let found = try detected(
            ["film.mkv", "film.original.srt", "film.original.ko.srt"],
            for: "film.mkv"
        )
        #expect(found.sorted() == ["film.original.ko.srt", "film.original.srt"])
    }

    /// Matching on the prefix alone would pull in the neighbouring film's subtitles.
    @Test func ignoresASimilarlyNamedNeighbour() throws {
        let found = try detected(["film.mkv", "film2.mkv", "film2.en.srt"], for: "film.mkv")
        #expect(found.isEmpty)
    }

    @Test func ignoresFilesThatAreNotSubtitles() throws {
        let found = try detected(["film.mkv", "film.txt", "film.nfo", "film.jpg"], for: "film.mkv")
        #expect(found.isEmpty)
    }

    @Test func acceptsTheOtherSupportedFormats() throws {
        let found = try detected(["film.mkv", "film.vtt", "film.smi"], for: "film.mkv")
        #expect(found.sorted() == ["film.smi", "film.vtt"])
    }

    @Test func hasNothingToFindInAnEmptyFolder() throws {
        #expect(try detected(["film.mkv"], for: "film.mkv").isEmpty)
    }
}
