import Foundation
import GlazeCore

actor EmbeddedSubtitleService {
    enum ServiceError: LocalizedError {
        case toolUnavailable
        case unsupportedTrack(String)
        case probeFailed(String)
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .toolUnavailable:
                "FFmpeg subtitle tools are unavailable."
            case .unsupportedTrack(let codec):
                "The embedded subtitle codec is not timed text: \(codec)."
            case .probeFailed(let message):
                "Embedded subtitle inspection failed: \(message)"
            case .extractionFailed(let message):
                "Embedded subtitle extraction failed: \(message)"
            }
        }
    }

    // Track discovery and the audio language tag both moved to `MediaProbeCoordinator`,
    // which reads the container once for every panel that needs it rather than
    // launching a separate ffprobe per question.

    func extract(track: EmbeddedSubtitleTrack, from mediaURL: URL) async throws -> URL {
        guard track.canProvideTimedText else {
            throw ServiceError.unsupportedTrack(track.codec)
        }

        guard let ffmpegURL = FFmpegTool.ffmpegURL else {
            throw ServiceError.toolUnavailable
        }

        let outputURL = try cachedSubtitleURL(for: mediaURL, track: track)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        _ = try await runForData(
            executableURL: ffmpegURL,
            arguments: [
                "-y",
                "-hide_banner",
                "-loglevel", "error",
                "-i", inputArgument(for: mediaURL),
                "-map", "0:\(track.streamIndex)",
                "-c:s", "srt",
                outputURL.path
            ],
            failure: ServiceError.extractionFailed
        )

        return outputURL
    }

    private func cachedSubtitleURL(for mediaURL: URL, track: EmbeddedSubtitleTrack) throws -> URL {
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Glaze", isDirectory: true)
        .appendingPathComponent("EmbeddedSubtitles", isDirectory: true)

        let baseName = mediaURL.deletingPathExtension().lastPathComponent
        let sourceHash = Self.fnv1aHash(mediaURL.absoluteString)
        let language = track.languageCode ?? "und"
        return cacheRoot.appendingPathComponent(
            "\(baseName)-\(sourceHash).embedded.\(language).stream-\(track.streamIndex).srt"
        )
    }

    private func inputArgument(for url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    private func runForData(
        executableURL: URL,
        arguments: [String],
        failure: @escaping @Sendable (String) -> ServiceError
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: failure(message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: failure(error.localizedDescription))
            }
        }
    }

    private static func fnv1aHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

private extension EmbeddedSubtitleService {
    struct ProbeResponse: Decodable {
        let streams: [ProbeStream]
    }

    struct ProbeStream: Decodable {
        let index: Int
        let codecName: String?
        let tags: ProbeTags?
        let disposition: ProbeDisposition?

        enum CodingKeys: String, CodingKey {
            case index
            case codecName = "codec_name"
            case tags
            case disposition
        }
    }

    struct ProbeTags: Decodable {
        let language: String?
        let title: String?
    }

    struct ProbeDisposition: Decodable {
        let defaultValue: Int?
        let forced: Int?

        enum CodingKeys: String, CodingKey {
            case defaultValue = "default"
            case forced
        }
    }
}
