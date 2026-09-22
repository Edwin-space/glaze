import Foundation
import GlazeCore

/// Stills for the timeline, cut from the film by the bundled ffmpeg.
///
/// The Mac has no VLCKit thumbnailer — it loads libvlc itself — but it does ship
/// ffmpeg for pulling audio out of a film, and the same tool will hand back a single
/// frame. Seeking before the input rather than after it is what makes this fast
/// enough to follow a pointer: ffmpeg jumps to the nearest keyframe instead of
/// decoding from the beginning.
struct FFmpegFrameSource: ScrubPreviewSource {
    let url: URL
    /// Wide enough to recognise a scene, small enough to decode and draw at once.
    var width = 320

    func frame(at time: TimeInterval) async -> Data? {
        guard let ffmpeg = FFmpegTool.ffmpegURL else { return nil }
        let arguments = [
            "-hide_banner",
            "-loglevel", "error",
            // Before -i: seek by jumping, not by decoding everything up to here.
            "-ss", String(format: "%.3f", max(time, 0)),
            "-i", url.isFileURL ? url.path : url.absoluteString,
            "-frames:v", "1",
            "-vf", "scale=\(width):-2",
            "-q:v", "6",
            "-f", "mjpeg",
            "pipe:1"
        ]
        return await Self.run(ffmpeg, arguments: arguments)
    }

    /// - Returns: what the tool wrote, or nil if it failed or wrote nothing.
    private static func run(_ executable: URL, arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors

            // Read while it runs: a frame is tens of kilobytes, and a pipe that fills
            // up stops the process rather than the other way round.
            let collected = UnsafeSendable(NSMutableData())
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                collected.value.append(chunk)
            }

            process.terminationHandler = { process in
                output.fileHandleForReading.readabilityHandler = nil
                _ = try? errors.fileHandleForReading.readToEnd()
                let data = collected.value as Data
                let succeeded = process.terminationStatus == 0 && !data.isEmpty
                continuation.resume(returning: succeeded ? data : nil)
            }

            do {
                try process.run()
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }

    /// The pipe's handler runs on a queue of Foundation's choosing, which is the only
    /// reason this exists: the buffer it appends to is touched from there and read
    /// once the process has ended, never at the same time.
    private final class UnsafeSendable<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }
}
