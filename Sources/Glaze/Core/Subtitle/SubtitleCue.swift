import Foundation

struct SubtitleCue: Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    func contains(_ time: TimeInterval) -> Bool {
        startTime <= time && time < endTime
    }
}
