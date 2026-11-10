import Foundation

/// Random access to timed text, including a seek into the middle of a cue.
/// No decoder history or network reads are needed to reconstruct the current line.
public struct SubtitleTimeline: Sendable {
    public let cues: [SubtitleCue]
    private let latestEnd: [TimeInterval]

    public init(cues: [SubtitleCue]) {
        self.cues = cues.filter {
            $0.startTime.isFinite && $0.endTime.isFinite && $0.endTime > $0.startTime && !$0.text.isEmpty
        }.sorted { $0.startTime < $1.startTime }
        var maximum: TimeInterval = -.infinity
        latestEnd = self.cues.map {
            maximum = max(maximum, $0.endTime)
            return maximum
        }
    }

    public func activeIndices(at time: TimeInterval) -> [Int] {
        guard time.isFinite else { return [] }
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if cues[middle].startTime <= time { lower = middle + 1 } else { upper = middle }
        }
        var index = lower - 1
        var result: [Int] = []
        // The prefix maximum preserves overlapping captions, including a long cue
        // that began before a shorter cue which has already ended.
        while index >= 0, latestEnd[index] > time {
            if cues[index].contains(time) { result.append(index) }
            index -= 1
        }
        return result.reversed()
    }

    public func text(at time: TimeInterval) -> String {
        activeIndices(at: time).map { cues[$0].text }.joined(separator: "\n")
    }
}
