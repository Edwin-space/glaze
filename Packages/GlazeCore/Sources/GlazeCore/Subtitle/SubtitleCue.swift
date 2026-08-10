import Foundation

public struct SubtitleCue: Equatable, Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String

    public init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }

    public func contains(_ time: TimeInterval) -> Bool {
        startTime <= time && time < endTime
    }
}
