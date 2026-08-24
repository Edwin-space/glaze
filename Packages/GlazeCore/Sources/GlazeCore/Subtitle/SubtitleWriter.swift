import Foundation

/// Writes `SubtitleCue` values back out to SRT. Counterpart to `SubtitleParser`'s read side.
public enum SubtitleWriter {
    public static func srt(from cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.startTime)) --> \(timestamp(cue.endTime))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// - Parameter relatedTo: the video this subtitle belongs beside. Under the App
    ///   Sandbox, writing next to an opened film is only permitted as a related item of
    ///   it — see `RelatedFileAccess`.
    public static func writeSRT(cues: [SubtitleCue], to url: URL, relatedTo videoURL: URL? = nil) throws {
        let content = srt(from: cues)
        let directory = url.deletingLastPathComponent()

        // The app library needs creating; the folder a film already lives in does not,
        // and asking the sandbox to create it is a permission error rather than a no-op.
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try RelatedFileAccess.write(Data(content.utf8), to: url, relatedTo: videoURL)
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
