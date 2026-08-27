import Foundation
import Testing
@testable import GlazeCore

struct SubtitleStoreTests {
    private func makeStore() -> (FileSubtitleStore, URL) {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-store-tests-\(UUID().uuidString)")
        return (FileSubtitleStore(libraryDirectory: library), library)
    }

    private let cues = [SubtitleCue(startTime: 0, endTime: 1, text: "안녕")]

    // MARK: - Destination policy

    @Test func besideVideoIsPreferredAndLibraryIsTheFallback() {
        let (store, library) = makeStore()
        let video = URL(fileURLWithPath: "/Volumes/NAS/Movies/movie.mkv")

        let destinations = store.destinations(
            for: .localFile(video),
            kind: .translated(languageCode: "ko"),
            preferring: .besideVideo
        )

        #expect(destinations.count == 2)
        #expect(destinations[0].path == "/Volumes/NAS/Movies/movie.ko.srt")
        #expect(destinations[1].deletingLastPathComponent().path == library.path)
    }

    @Test func appLibraryChoiceDoesNotOfferTheVideoFolder() {
        let (store, _) = makeStore()
        let video = URL(fileURLWithPath: "/Users/someone/Movies/movie.mkv")

        let destinations = store.destinations(
            for: .localFile(video),
            kind: .generated(languageCode: "ja"),
            preferring: .appLibrary
        )

        #expect(destinations.count == 1)
        #expect(!destinations[0].path.hasPrefix("/Users/someone/Movies"))
    }

    /// A streamed video has no folder to sit beside, so the preference cannot apply.
    @Test func networkResourceFallsBackToTheLibraryEvenWhenBesideIsPreferred() {
        let (store, library) = makeStore()
        let resource = MediaResource.network(
            NetworkMediaResource(
                serverID: "server-1",
                objectID: "obj/42",
                playbackURL: URL(string: "http://nas.local/media/42")!
            )
        )

        let destinations = store.destinations(
            for: resource,
            kind: .generated(languageCode: "ja"),
            preferring: .besideVideo
        )

        #expect(destinations.count == 1)
        #expect(destinations[0].deletingLastPathComponent().path == library.path)
    }

    /// Object ids can contain path separators, which would otherwise create
    /// directories that do not exist.
    @Test func networkIdentifierIsSafeAsAFilename() {
        let resource = MediaResource.network(
            NetworkMediaResource(
                serverID: "srv",
                objectID: "folder/item",
                playbackURL: URL(string: "http://nas.local/x")!
            )
        )

        #expect(!FileSubtitleStore.identifier(for: resource).contains("/"))
    }

    @Test func generatedAndTranslatedDoNotCollide() {
        let (store, _) = makeStore()
        let video = URL(fileURLWithPath: "/tmp/movie.mkv")

        let generated = store.destinations(for: .localFile(video), kind: .generated(languageCode: "ja"), preferring: .besideVideo)[0]
        let translated = store.destinations(
            for: .localFile(video),
            kind: .translated(languageCode: "ko"),
            preferring: .besideVideo
        )[0]

        #expect(generated.lastPathComponent == "movie.ja.srt")
        #expect(translated.lastPathComponent == "movie.ko.srt")
    }

    // MARK: - Writing

    @Test func writesBesideTheVideoWhenTheFolderIsWritable() throws {
        let (store, _) = makeStore()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-beside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let video = folder.appendingPathComponent("movie.mkv")
        try Data().write(to: video)

        let written = try store.save(
            cues: cues,
            for: .localFile(video),
            kind: .translated(languageCode: "ko"),
            preferring: .besideVideo
        )

        #expect(written.deletingLastPathComponent().path == folder.path)
        #expect(FileManager.default.fileExists(atPath: written.path))
    }

    /// The point of the fallback: an unwritable video folder must not lose a
    /// translation the user waited for.
    @Test func fallsBackToTheLibraryWhenTheVideoFolderRejectsTheWrite() throws {
        let (store, library) = makeStore()
        defer { try? FileManager.default.removeItem(at: library) }

        // A path under a file, which cannot be a directory.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let video = blocker.appendingPathComponent("nested").appendingPathComponent("movie.mkv")

        let written = try store.save(
            cues: cues,
            for: .localFile(video),
            kind: .generated(languageCode: "ja"),
            preferring: .besideVideo
        )

        #expect(written.deletingLastPathComponent().path == library.path)
        #expect(FileManager.default.fileExists(atPath: written.path))
    }

    @Test func writtenFileParsesBackToTheSameCues() throws {
        let (store, library) = makeStore()
        defer { try? FileManager.default.removeItem(at: library) }

        let written = try store.save(
            cues: [
                SubtitleCue(startTime: 0, endTime: 2, text: "첫 줄"),
                SubtitleCue(startTime: 2, endTime: 4, text: "둘째 줄")
            ],
            for: .localFile(URL(fileURLWithPath: "/tmp/does-not-exist/movie.mkv")),
            kind: .generated(languageCode: "ja"),
            preferring: .appLibrary
        )

        let parsed = try SubtitleParser.parse(url: written)
        #expect(parsed.map(\.text) == ["첫 줄", "둘째 줄"])
        #expect(parsed[1].startTime == 2)
    }
}

/// The names have to be the ones other media servers already read. Jellyfin, Emby and
/// Kodi all take `Film.ko.srt` as a Korean subtitle for `Film.mkv`; none of them
/// understands `Film.original.ko.srt`, which is what this used to write.
struct SubtitleNamingCompatibilityTests {
    private let store = FileSubtitleStore(libraryDirectory: URL(fileURLWithPath: "/tmp/lib"))
    private let video = MediaResource.localFile(URL(fileURLWithPath: "/Movies/Film.mkv"))

    @Test func aTranslationIsNamedForItsLanguage() {
        let destination = store.destinations(
            for: video,
            kind: .translated(languageCode: "ko"),
            preferring: .besideVideo
        )[0]

        #expect(destination.lastPathComponent == "Film.ko.srt")
    }

    /// A transcription is labelled with what was spoken, so a server shelving it knows
    /// what language it is looking at.
    @Test func aTranscriptionIsNamedForTheSpokenLanguage() {
        let destination = store.destinations(
            for: video,
            kind: .generated(languageCode: "ja"),
            preferring: .besideVideo
        )[0]

        #expect(destination.lastPathComponent == "Film.ja.srt")
    }

    /// Whisper does not always report a language. `und` is the code containers use for
    /// exactly this, so it stays readable rather than becoming `Film..srt`.
    @Test func anUnknownLanguageIsMarkedUndetermined() {
        let destination = store.destinations(
            for: video,
            kind: .generated(languageCode: nil),
            preferring: .besideVideo
        )[0]

        #expect(destination.lastPathComponent == "Film.und.srt")
    }

    @Test func aliasesAndRegionsUseThePortableLanguageCode() {
        let japanese = store.destinations(
            for: video,
            kind: .generated(languageCode: "jpn-JP"),
            preferring: .besideVideo
        )[0]
        let korean = store.destinations(
            for: video,
            kind: .translated(languageCode: "kor_KR"),
            preferring: .besideVideo
        )[0]

        #expect(japanese.lastPathComponent == "Film.ja.srt")
        #expect(korean.lastPathComponent == "Film.ko.srt")
    }

    @Test func anInvalidLanguageDoesNotBecomeAnArbitraryFilenameSuffix() {
        let destination = store.destinations(
            for: video,
            kind: .generated(languageCode: "translated"),
            preferring: .besideVideo
        )[0]

        #expect(destination.lastPathComponent == "Film.und.srt")
    }
}
