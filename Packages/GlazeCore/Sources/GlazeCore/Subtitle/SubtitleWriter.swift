import Foundation

/// Writes `SubtitleCue` values back out to SRT. Counterpart to `SubtitleParser`'s read side.
public enum SubtitleWriter {
    public static func srt(from cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.startTime)) --> \(timestamp(cue.endTime))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    public static func writeSRT(cues: [SubtitleCue], to url: URL) throws {
        let content = srt(from: cues)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func timestamp(_ time: TimeInterval) -> String {
        let totalMilliseconds = Int((max(0, time) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
