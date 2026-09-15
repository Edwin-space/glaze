import Foundation

/// One thing that can be played from a queue.
public struct PlaybackQueueItem: Identifiable, Equatable, Sendable {
    public let resource: NetworkMediaResource
    public let title: String

    public var id: String { resource.objectID }

    public init(resource: NetworkMediaResource, title: String) {
        self.resource = resource
        self.title = title
    }
}

/// The films around the one playing, and which way is next.
///
/// A folder of episodes is the commonest thing anyone plays, and the phone could only
/// play one file and stop: no previous, no next, no way to see what else was there
/// without closing the film. The Mac had all of it, in its own terms. This is the rule
/// written once, so the phone and the television move through a folder the same way.
///
/// A value type: moving through it returns what to play, and the caller decides whether
/// to actually play it. Nothing here touches a player.
public struct PlaybackQueue: Equatable, Sendable {
    public private(set) var items: [PlaybackQueueItem]
    public private(set) var index: Int

    /// - Parameters:
    ///   - items: the films around it, in reading order.
    ///   - current: the film chosen. Taken whole rather than as an id, so that a list
    ///     which does not contain it still plays *it* — a queue of just that film,
    ///     rather than whichever film happened to be first.
    public init(items: [PlaybackQueueItem], current: PlaybackQueueItem) {
        if let position = items.firstIndex(where: { $0.id == current.id }) {
            self.items = items
            index = position
        } else {
            self.items = [current]
            index = 0
        }
    }

    public var current: PlaybackQueueItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// Worth showing the controls at all. A single film has nowhere to go.
    public var isNavigable: Bool { items.count > 1 }

    public var next: PlaybackQueueItem? {
        items.indices.contains(index + 1) ? items[index + 1] : nil
    }

    public var previous: PlaybackQueueItem? {
        items.indices.contains(index - 1) ? items[index - 1] : nil
    }

    /// - Returns: the film to play, or nil at the end of the folder — which is where
    ///   automatic playback should stop rather than wrap round to the first episode.
    @discardableResult
    public mutating func advance() -> PlaybackQueueItem? {
        guard next != nil else { return nil }
        index += 1
        return current
    }

    @discardableResult
    public mutating func retreat() -> PlaybackQueueItem? {
        guard previous != nil else { return nil }
        index -= 1
        return current
    }

    @discardableResult
    public mutating func jump(to id: String) -> PlaybackQueueItem? {
        guard let position = items.firstIndex(where: { $0.id == id }) else { return nil }
        index = position
        return current
    }

    /// What "previous" should mean a few seconds in.
    ///
    /// Every player people use restarts the current film when you are already into it,
    /// and only goes back a file when you press again at the very start. Jumping to the
    /// previous episode from minute forty is almost never what was meant.
    public static let restartThreshold: TimeInterval = 5
}
