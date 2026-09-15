import Foundation
import Testing
@testable import GlazeCore

@Suite
struct PlaybackQueueTests {
    private func item(_ name: String) -> PlaybackQueueItem {
        PlaybackQueueItem(
            resource: NetworkMediaResource(
                serverID: "nas",
                objectID: name,
                playbackURL: URL(string: "https://nas/\(name)")!,
                subtitleResources: []
            ),
            title: name
        )
    }

    private var three: [PlaybackQueueItem] { ["E01", "E02", "E03"].map(item) }

    @Test("Starts on the film that was chosen, not the first in the folder")
    func startsWhereAsked() {
        let queue = PlaybackQueue(items: three, current: item("E02"))
        #expect(queue.current?.id == "E02")
        #expect(queue.previous?.id == "E01")
        #expect(queue.next?.id == "E03")
    }

    /// Automatic playback stops at the end of a folder. Wrapping round to the first
    /// episode after the last one finishes is not what anyone watching a run wants.
    @Test("Stops at the ends rather than wrapping round")
    func stopsAtTheEnds() {
        var queue = PlaybackQueue(items: three, current: item("E03"))
        #expect(queue.advance() == nil)
        #expect(queue.current?.id == "E03")

        var start = PlaybackQueue(items: three, current: item("E01"))
        #expect(start.retreat() == nil)
        #expect(start.current?.id == "E01")
    }

    @Test("Moves forward, back, and straight to a chosen film")
    func moves() {
        var queue = PlaybackQueue(items: three, current: item("E01"))
        #expect(queue.advance()?.id == "E02")
        #expect(queue.advance()?.id == "E03")
        #expect(queue.retreat()?.id == "E02")
        #expect(queue.jump(to: "E01")?.id == "E01")
        #expect(queue.jump(to: "nope") == nil)
        #expect(queue.current?.id == "E01")
    }

    @Test("A single film has nowhere to go")
    func singleFilm() {
        let queue = PlaybackQueue(items: [item("Only")], current: item("Only"))
        #expect(!queue.isNavigable)
        #expect(queue.next == nil && queue.previous == nil)
    }

    /// It used to fall back to the folder's first film — a different film from the one
    /// that was tapped. The count was right and the film was wrong.
    @Test("A queue that does not hold the chosen film plays that film, not another")
    func missingStart() {
        let queue = PlaybackQueue(items: three, current: item("E09"))
        #expect(queue.items.count == 1)
        #expect(queue.current?.id == "E09")
    }
}
