import Foundation

/// One native seek in flight; only the latest subsequent target is retained.
/// A token prevents a delayed completion from finishing another seek or film.
public struct PlaybackSeekQueue: Sendable {
    public struct Request: Equatable, Sendable {
        public let id = UUID()
        public let sequence: Int
        public let target: TimeInterval
    }

    public private(set) var active: Request?
    public private(set) var queued: Request?
    private var sequence = 0

    public init() {}

    @discardableResult
    public mutating func enqueue(target: TimeInterval) -> Request? {
        guard target.isFinite, target >= 0 else { return nil }
        sequence += 1
        let request = Request(sequence: sequence, target: target)
        if active != nil {
            // Returning to the active target cancels an intermediate queued seek.
            queued = active?.target == target ? nil : request
            return nil
        }
        active = request
        return request
    }

    /// Returns the next native operation, or nil for a stale/final completion.
    @discardableResult
    public mutating func finish(id: UUID) -> Request? {
        guard active?.id == id else { return nil }
        active = queued
        queued = nil
        return active
    }

    public mutating func reset() {
        active = nil
        queued = nil
        sequence = 0
    }
}
