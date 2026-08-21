import Foundation
import Testing
@testable import GlazeCore

struct PlaybackPositionStoreTests {
    private func makeStore() -> (PlaybackPositionStore, UserDefaults) {
        let suite = UserDefaults(suiteName: "glaze-position-tests-\(UUID().uuidString)")!
        return (PlaybackPositionStore(defaults: suite), suite)
    }

    private let movie = MediaResource.localFile(URL(fileURLWithPath: "/tmp/movie.mkv"))

    @Test func remembersAndReturnsAPosition() {
        let (store, _) = makeStore()

        store.record(600, duration: 3_600, for: movie)

        #expect(store.position(for: movie) == 600)
    }

    @Test func hasNothingToResumeForAnUnseenVideo() {
        let (store, _) = makeStore()

        #expect(store.position(for: movie) == nil)
    }

    /// Resuming a few seconds in is worse than starting over — it looks like a bug.
    @Test func ignoresPositionsInTheOpeningSeconds() {
        let (store, _) = makeStore()

        store.record(4, duration: 3_600, for: movie)

        #expect(store.position(for: movie) == nil)
    }

    /// A finished video should replay from the start, not from its closing seconds.
    @Test func forgetsAVideoWatchedToTheEnd() {
        let (store, _) = makeStore()
        store.record(600, duration: 3_600, for: movie)

        store.record(3_580, duration: 3_600, for: movie)

        #expect(store.position(for: movie) == nil)
    }

    @Test func keepsPositionJustBeforeTheWatchedThreshold() {
        let (store, _) = makeStore()

        store.record(3_400, duration: 3_600, for: movie)

        #expect(store.position(for: movie) == 3_400)
    }

    /// Duration is unknown while a stream is still opening; a zero must not be read
    /// as "finished" and wipe a real position.
    @Test func toleratesUnknownDuration() {
        let (store, _) = makeStore()

        store.record(600, duration: 0, for: movie)

        #expect(store.position(for: movie) == 600)
    }

    @Test func tracksEachVideoSeparately() {
        let (store, _) = makeStore()
        let other = MediaResource.localFile(URL(fileURLWithPath: "/tmp/other.mkv"))

        store.record(600, duration: 3_600, for: movie)
        store.record(120, duration: 3_600, for: other)

        #expect(store.position(for: movie) == 600)
        #expect(store.position(for: other) == 120)
    }

    @Test func networkResourcesResumeLikeLocalOnes() {
        let (store, _) = makeStore()
        let streamed = MediaResource.network(
            NetworkMediaResource(
                serverID: "nas",
                objectID: "42",
                playbackURL: URL(string: "http://nas.local/42")!
            )
        )

        store.record(900, duration: 3_600, for: streamed)

        #expect(store.position(for: streamed) == 900)
    }

    @Test func forgetClearsAPosition() {
        let (store, _) = makeStore()
        store.record(600, duration: 3_600, for: movie)

        store.forget(movie)

        #expect(store.position(for: movie) == nil)
    }
}
