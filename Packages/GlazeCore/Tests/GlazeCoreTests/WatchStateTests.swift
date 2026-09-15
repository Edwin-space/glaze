import Foundation
import Testing
@testable import GlazeCore

/// What a list shows for a film: new, part-watched, or watched.
///
/// Before this, finishing a film erased its record — correctly, so a replay starts from
/// the top — which left "watched" and "never played" looking identical. No list could
/// mark the new episodes in a folder, which is the thing people look for.
@Suite
struct WatchStateTests {
    private func store() -> PlaybackPositionStore {
        PlaybackPositionStore(defaults: UserDefaults(suiteName: "watch-\(UUID().uuidString)")!)
    }

    private let film = MediaResource.localFile(URL(fileURLWithPath: "/films/E01.mkv"))

    @Test("A film never played is new")
    func new() {
        #expect(store().state(for: film) == .new)
    }

    @Test("A film left partway reports how far through it is")
    func inProgress() {
        let store = store()
        store.record(1_200, duration: 2_400, for: film)
        #expect(store.state(for: film) == .inProgress(0.5))
    }

    /// The whole point: finishing must not make a film look unplayed again.
    @Test("A film watched to the end is watched, not new")
    func watched() {
        let store = store()
        store.record(1_200, duration: 2_400, for: film)
        store.record(2_390, duration: 2_400, for: film)
        #expect(store.state(for: film) == .watched)
    }

    /// And resuming must still behave as it always did — a finished film starts over.
    @Test("Finishing still clears the resume position")
    func finishingStillStartsOver() {
        let store = store()
        store.record(2_390, duration: 2_400, for: film)
        #expect(store.position(for: film) == nil)
    }

    @Test("Watching a finished film again reads as in progress until it is done")
    func rewatch() {
        let store = store()
        store.record(2_390, duration: 2_400, for: film)
        store.record(600, duration: 2_400, for: film)
        #expect(store.state(for: film) == .inProgress(0.25))
    }

    @Test("A film can be marked back to unwatched")
    func markUnwatched() {
        let store = store()
        store.record(2_390, duration: 2_400, for: film)
        store.markUnwatched(film)
        #expect(store.state(for: film) == .new)
    }

    /// The first seconds of playback report a position of zero. That must not turn a
    /// new film into "started".
    @Test("Opening a film and closing it at once leaves it new")
    func barelyStarted() {
        let store = store()
        store.record(3, duration: 2_400, for: film)
        #expect(store.state(for: film) == .new)
    }
}
