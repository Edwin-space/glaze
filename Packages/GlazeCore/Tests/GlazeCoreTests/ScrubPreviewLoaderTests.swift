import Foundation
import GlazeCore
import Testing

/// Counts what it was asked for, and answers straight away.
private actor RecordingSource: ScrubPreviewSource {
    private(set) var asked: [TimeInterval] = []

    func frame(at time: TimeInterval) async -> Data? {
        asked.append(time)
        return Data("\(time)".utf8)
    }
}

@Suite("Showing a still while the thumb moves along the timeline")
@MainActor
struct ScrubPreviewLoaderTests {
    @Test("Times are rounded to the step, so a wobbling thumb asks once")
    func roundsToTheStep() {
        let loader = ScrubPreviewLoader(source: RecordingSource(), step: 5)
        #expect(loader.bucket(for: 11.2) == 10)
        #expect(loader.bucket(for: 12.6) == 15)
        #expect(loader.bucket(for: -4) == 0)
    }

    @Test("A time already taken comes back without asking again")
    func reusesWhatItHas() async throws {
        let source = RecordingSource()
        let loader = ScrubPreviewLoader(source: source, step: 5)

        loader.request(30)
        try await untilFrame(loader)
        #expect(loader.frameTime == 30)

        loader.request(31)
        #expect(loader.frame == Data("30.0".utf8))
        #expect(await source.asked == [30])
    }

    @Test("While one frame is being made, only the newest request waits")
    func dropsWhatWasOvertaken() async throws {
        let source = RecordingSource()
        let loader = ScrubPreviewLoader(source: source, step: 5)

        loader.request(10)
        loader.request(20)
        loader.request(30)
        try await untilFrame(loader, matching: 30)

        // The first request was already running; 20 was overtaken by 30 and dropped.
        #expect(await source.asked == [10, 30])
        #expect(loader.frameTime == 30)
    }

    @Test("Letting go clears the picture")
    func clearsWhenTheDragEnds() async throws {
        let loader = ScrubPreviewLoader(source: RecordingSource(), step: 5)
        loader.request(45)
        try await untilFrame(loader)
        loader.clear()
        #expect(loader.frame == nil)
        #expect(loader.frameTime == nil)
    }

    @Test("Without a source nothing is asked for and nothing is shown")
    func staysQuietWithoutASource() {
        let loader = ScrubPreviewLoader(source: nil)
        #expect(loader.isAvailable == false)
        loader.request(10)
        #expect(loader.frame == nil)
    }

    private func untilFrame(
        _ loader: ScrubPreviewLoader,
        matching time: TimeInterval? = nil
    ) async throws {
        for _ in 0..<200 {
            if let time {
                if loader.frameTime == time { return }
            } else if loader.frame != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("no frame arrived")
    }
}
