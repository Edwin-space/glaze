import Foundation
import Observation

/// Something that can produce a still from a film at a given time.
///
/// Each platform has its own way: VLCKit's thumbnailer on the phone and the
/// television, the bundled ffmpeg on the Mac. What they hand back is image bytes
/// rather than a picture object, because the work happens off the main actor and a
/// `CGImage` cannot cross that line.
public protocol ScrubPreviewSource: Sendable {
    /// - Returns: JPEG bytes for the frame at that time, or nil when the film cannot
    ///   be read at that point.
    func frame(at time: TimeInterval) async -> Data?
}

/// The still shown while someone drags along the timeline.
///
/// Dragging produces a position several times a second, and decoding a frame takes
/// far longer than that. So requests are rounded to a step, a time already taken is
/// answered from memory, and while one frame is being made only the newest request
/// waits — everything in between is dropped rather than queued, which is what keeps
/// the picture up with the thumb instead of minutes behind it.
@MainActor
@Observable
public final class ScrubPreviewLoader {
    /// The frame to show now, and the time it was taken at.
    public private(set) var frame: Data?
    public private(set) var frameTime: TimeInterval?
    public private(set) var isWorking = false

    /// How far apart the frames are. Five seconds is finer than anyone can aim on a
    /// two-hour film and keeps the cache small.
    public let step: TimeInterval

    private let source: ScrubPreviewSource?
    private var cache: [TimeInterval: Data] = [:]
    private var order: [TimeInterval] = []
    private var pending: TimeInterval?
    private var task: Task<Void, Never>?

    /// Frames kept in memory. A 320-wide JPEG is tens of kilobytes.
    private let cacheLimit = 60

    public init(source: ScrubPreviewSource?, step: TimeInterval = 5) {
        self.source = source
        self.step = max(step, 1)
    }

    public var isAvailable: Bool { source != nil }

    /// Asks for the frame at a time on the timeline.
    public func request(_ time: TimeInterval) {
        guard source != nil else { return }
        let wanted = bucket(for: time)

        if let cached = cache[wanted] {
            frame = cached
            frameTime = wanted
            pending = nil
            return
        }

        pending = wanted
        guard task == nil else { return }
        run()
    }

    /// Called when the drag ends: the picture has done its job.
    public func clear() {
        pending = nil
        task?.cancel()
        task = nil
        isWorking = false
        frame = nil
        frameTime = nil
    }

    /// Rounds to the nearest step, so a wobbling thumb asks for the same frame twice
    /// rather than for two frames a tenth of a second apart.
    public func bucket(for time: TimeInterval) -> TimeInterval {
        (max(time, 0) / step).rounded() * step
    }

    private func run() {
        guard let source, let wanted = pending else { return }
        pending = nil
        isWorking = true
        task = Task { [weak self] in
            let data = await source.frame(at: wanted)
            guard let self, !Task.isCancelled else { return }
            if let data {
                remember(data, at: wanted)
                // A frame that arrived after the thumb moved on is still worth
                // keeping, but only the newest one belongs on screen.
                if pending == nil {
                    frame = data
                    frameTime = wanted
                }
            }
            task = nil
            isWorking = false
            if pending != nil { run() }
        }
    }

    private func remember(_ data: Data, at time: TimeInterval) {
        if cache[time] == nil { order.append(time) }
        cache[time] = data
        while order.count > cacheLimit {
            cache.removeValue(forKey: order.removeFirst())
        }
    }
}
