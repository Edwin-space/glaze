import Foundation
import GlazeCore

/// Turns an ASS/SSA sidecar into the SRT the parser reads, using the ffmpeg already
/// bundled for embedded-track extraction. Lives on the Mac side because `Process` is
/// the part of this that Apple TV cannot run.
enum FFmpegSubtitleConverter {
    enum ConversionError: Error {
        case toolUnavailable
        case failed
    }

    static let convert: NetworkSubtitleLoader.SubtitleConverter = { source, destination in
        guard let ffmpegURL = FFmpegTool.ffmpegURL else { throw ConversionError.toolUnavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = [
                "-y", "-hide_banner", "-loglevel", "error",
                "-i", source.path,
                destination.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                process.terminationStatus == 0
                    ? continuation.resume()
                    : continuation.resume(throwing: ConversionError.failed)
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
    }
}
