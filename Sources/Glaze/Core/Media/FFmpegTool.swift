import Foundation

enum FFmpegTool {
    static var ffmpegURL: URL? {
        candidateExecutableURLs(named: "ffmpeg").first
    }

    static var ffprobeURL: URL? {
        candidateExecutableURLs(named: "ffprobe").first
    }

    private static func candidateExecutableURLs(named toolName: String) -> [URL] {
        var candidates: [URL] = []

        candidates.append(contentsOf: bundledExecutableURLs(named: toolName))

        let pathCandidates = [
            "/opt/homebrew/bin/\(toolName)",
            "/usr/local/bin/\(toolName)",
            "/usr/bin/\(toolName)"
        ].map(URL.init(fileURLWithPath:))

        candidates.append(contentsOf: pathCandidates)

        return candidates.filter { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func bundledExecutableURLs(named toolName: String) -> [URL] {
        var candidates: [URL] = []

        if let bundledURL = Bundle.main.url(forResource: toolName, withExtension: nil, subdirectory: "Tools") {
            candidates.append(bundledURL)
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Tools/\(toolName)"))
            candidates.append(resourceURL.appendingPathComponent(toolName))
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Tools/\(toolName)"))

        if let bundledURL = Bundle.main.url(forResource: toolName, withExtension: nil) {
            candidates.append(bundledURL)
        }

        return candidates
    }
}

enum FFmpegRemuxer {
    private static let cacheVersion = "v2"

    enum RemuxError: Error {
        case toolUnavailable
        case unsupportedVideoCodec(String)
        case failed([AttemptFailure])
    }

    struct AttemptFailure: Error {
        let mode: Mode
        let message: String
    }

    enum Mode: String {
        case streamCopy = "stream-copy"
        case audioAAC = "audio-aac"
    }

    static func remuxForAVPlayer(inputURL: URL) async throws -> URL {
        guard let ffmpegURL = FFmpegTool.ffmpegURL else {
            throw RemuxError.toolUnavailable
        }

        let codecName = try await primaryVideoCodecName(inputURL: inputURL)

        if let codecName, !isAVPlayerCandidateVideoCodec(codecName) {
            throw RemuxError.unsupportedVideoCodec(codecName)
        }

        var failures: [AttemptFailure] = []

        for mode in [Mode.audioAAC, .streamCopy] {
            let outputURL = try outputURL(for: inputURL, mode: mode)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                return outputURL
            }

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            do {
                try await run(
                    ffmpegURL: ffmpegURL,
                    arguments: arguments(inputURL: inputURL, outputURL: outputURL, mode: mode, codecName: codecName),
                    mode: mode
                )
                return outputURL
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                failures.append(AttemptFailure(mode: mode, message: remuxFailureMessage(from: error)))
            }
        }

        throw RemuxError.failed(failures)
    }

    private static func arguments(inputURL: URL, outputURL: URL, mode: Mode, codecName: String?) -> [String] {
        let baseArguments = [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", inputURL.path,
            "-map", "0:v:0",
        ]

        let codecArguments: [String]
        switch mode {
        case .streamCopy:
            codecArguments = [
                "-map", "0:a?",
                "-sn",
                "-dn",
                "-c", "copy"
            ]
        case .audioAAC:
            codecArguments = [
                "-map", "0:a:0?",
                "-sn",
                "-dn",
                "-c:v", "copy",
                "-c:a", "aac",
                "-b:a", "192k",
                "-ac", "2"
            ]
        }

        let videoTagArguments = codecName?.lowercased() == "hevc" ? ["-tag:v", "hvc1"] : []
        let outputArguments = [
            "-movflags", "+faststart",
            outputURL.path
        ]

        return baseArguments + codecArguments + videoTagArguments + outputArguments
    }

    private static func run(ffmpegURL: URL, arguments: [String], mode: Mode) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = ffmpegURL
            process.arguments = arguments
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AttemptFailure(mode: mode, message: errorText))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func outputURL(for inputURL: URL, mode: Mode) throws -> URL {
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Glaze", isDirectory: true)
        .appendingPathComponent("CompatibilityCache", isDirectory: true)

        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let hash = fnv1aHash(inputURL.path)
        return cacheRoot.appendingPathComponent("\(baseName)-\(hash)-\(cacheVersion)-\(mode.rawValue).mp4")
    }

    private static func remuxFailureMessage(from error: Error) -> String {
        if let failure = error as? AttemptFailure {
            return failure.message
        }

        return error.localizedDescription
    }

    private static func primaryVideoCodecName(inputURL: URL) async throws -> String? {
        guard let ffprobeURL = FFmpegTool.ffprobeURL else {
            return nil
        }

        let output = try await runForOutput(
            executableURL: ffprobeURL,
            arguments: [
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=codec_name",
                "-of", "default=noprint_wrappers=1:nokey=1",
                inputURL.path
            ]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return output.isEmpty ? nil : output
    }

    private static func isAVPlayerCandidateVideoCodec(_ codecName: String) -> Bool {
        [
            "h264",
            "hevc",
            "mpeg4",
            "prores",
            "mjpeg"
        ].contains(codecName.lowercased())
    }

    private static func runForOutput(executableURL: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(data: outputData, encoding: .utf8) ?? ""
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: outputText)
                } else {
                    continuation.resume(throwing: AttemptFailure(mode: .audioAAC, message: errorText))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
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
