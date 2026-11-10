import Foundation
import XCTest
@testable import GlazeCore

final class SubtitleSeekRecoveryTests: XCTestCase {
    private let timeline = SubtitleTimeline(cues: [
        .init(startTime: 10, endTime: 20, text: "long"),
        .init(startTime: 12, endTime: 14, text: "short"),
        .init(startTime: 30, endTime: 35, text: "later")
    ])

    func testSeekingIntoACueDoesNotWaitForTheNextCue() {
        XCTAssertEqual(timeline.text(at: 17), "long")
        XCTAssertEqual(timeline.text(at: 32), "later")
        XCTAssertEqual(timeline.text(at: 11), "long") // backwards, no cursor history
        XCTAssertTrue(timeline.text(at: 20).isEmpty) // exclusive end
        XCTAssertTrue(timeline.text(at: 25).isEmpty) // a real gap is not a delay
        XCTAssertTrue(timeline.text(at: .nan).isEmpty)
    }

    func testOverlappingAndInvalidCuesAreHandled() {
        XCTAssertEqual(timeline.text(at: 13), "long\nshort")
        XCTAssertEqual(timeline.activeIndices(at: 18), [0])
        let invalid = SubtitleTimeline(cues: [
            .init(startTime: .nan, endTime: 20, text: "bad"),
            .init(startTime: 4, endTime: 2, text: "backwards"),
            .init(startTime: 1, endTime: 3, text: "valid")
        ])
        XCTAssertEqual(invalid.cues.count, 1)
        XCTAssertEqual(invalid.text(at: 2), "valid")
    }

    func testOnlyTheNewestSeekRunsAfterAnActiveSeek() throws {
        var queue = PlaybackSeekQueue()
        let first = try XCTUnwrap(queue.enqueue(target: 10))
        XCTAssertNil(queue.enqueue(target: 20))
        XCTAssertNil(queue.enqueue(target: 30))
        XCTAssertEqual(queue.active, first)
        let next = try XCTUnwrap(queue.finish(id: first.id))
        XCTAssertEqual(next.target, 30)
        XCTAssertNil(queue.queued)
        XCTAssertNil(queue.finish(id: first.id)) // old callback cannot finish next
        XCTAssertEqual(queue.active, next)
        XCTAssertNil(queue.finish(id: next.id))
        XCTAssertNil(queue.active)
    }

    func testResetRejectsAnotherFilmsCompletionAndInvalidTargets() throws {
        var queue = PlaybackSeekQueue()
        XCTAssertNil(queue.enqueue(target: .nan))
        XCTAssertNil(queue.enqueue(target: -1))
        let old = try XCTUnwrap(queue.enqueue(target: 25))
        queue.reset()
        let fresh = try XCTUnwrap(queue.enqueue(target: 40))
        XCTAssertNil(queue.finish(id: old.id))
        XCTAssertEqual(queue.active, fresh)
    }

    func testReturningToTheInFlightTargetDropsAnIntermediateJump() throws {
        var queue = PlaybackSeekQueue()
        let first = try XCTUnwrap(queue.enqueue(target: 10))
        queue.enqueue(target: 20)
        queue.enqueue(target: 10)
        XCTAssertNil(queue.queued)
        XCTAssertNil(queue.finish(id: first.id))
    }
}
