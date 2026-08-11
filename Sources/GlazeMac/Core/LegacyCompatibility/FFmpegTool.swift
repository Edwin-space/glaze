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

        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDirectory.appendingPathComponent(toolName))
            candidates.append(executableDirectory.appendingPathComponent("Tools/\(toolName)"))
        }

        // Legacy resource locations remain as development fallbacks for older bundles.
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
    private static let cacheVersion = "v4"
    private static let progressiveReadyByteCount: UInt64 = 512 * 1024
    private static let progressiveMinimumByteCount: UInt64 = 64 * 1024
    private static let progressivePollInterval: UInt64 = 50_000_000
    private static let progressiveStartupTimeout: UInt64 = 5_000_000_000

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
        let audioCodecName = try await primaryAudioCodecName(inputURL: inputURL)

        if let codecName, !isAVPlayerCandidateVideoCodec(codecName) {
            throw RemuxError.unsupportedVideoCodec(codecName)
        }

        var failures: [AttemptFailure] = []

        for mode in preferredModes(forAudioCodec: audioCodecName) {
            let outputURL = try outputURL(for: inputURL, mode: mode)
            if isCompletedCache(outputURL) {
                return outputURL
            }

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            do {
                try removeStaleCacheIfNeeded(outputURL)
                let arguments = arguments(inputURL: inputURL, outputURL: outputURL, mode: mode, codecName: codecName)

                switch mode {
                case .streamCopy:
                    try await runProgressively(
                        ffmpegURL: ffmpegURL,
                        arguments: arguments,
                        mode: mode,
                        outputURL: outputURL
                    )
                case .audioAAC:
                    try await run(ffmpegURL: ffmpegURL, arguments: arguments, mode: mode)
                    markCompletedCache(outputURL)
                }

                return outputURL
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                try? FileManager.default.removeItem(at: completionMarkerURL(for: outputURL))
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
        let outputArguments: [String]
        switch mode {
        case .streamCopy:
            outputArguments = [
                "-movflags", "+empty_moov+default_base_moof+frag_keyframe",
                outputURL.path
            ]
        case .audioAAC:
            outputArguments = [
                "-movflags", "+faststart",
                outputURL.path
            ]
        }

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

    private static func runProgressively(
        ffmpegURL: URL,
        arguments: [String],
        mode: Mode,
        outputURL: URL
    ) async throws {
        if let process = FFmpegProcessRegistry.shared.process(for: outputURL.path) {
            try await waitForProgressiveOutput(outputURL: outputURL, process: process, mode: mode)
            return
        }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = ffmpegURL
        process.arguments = arguments
        process.standardError = errorPipe

        process.terminationHandler = { process in
            let isExposed = FFmpegProcessRegistry.shared.isExposed(outputPath: outputURL.path)

            if process.terminationStatus == 0 {
                markCompletedCache(outputURL)
            } else if !isExposed {
                _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
                try? FileManager.default.removeItem(at: outputURL)
                try? FileManager.default.removeItem(at: completionMarkerURL(for: outputURL))
            }

            FFmpegProcessRegistry.shared.remove(for: outputURL.path)
        }

        do {
            try process.run()
            FFmpegProcessRegistry.shared.set(process, for: outputURL.path)
            try await waitForProgressiveOutput(outputURL: outputURL, process: process, mode: mode)
        } catch {
            process.terminate()
            FFmpegProcessRegistry.shared.remove(for: outputURL.path)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: completionMarkerURL(for: outputURL))
            throw error
        }
    }

    private static func waitForProgressiveOutput(outputURL: URL, process: Process, mode: Mode) async throws {
        var waitedNanoseconds: UInt64 = 0

        while true {
            try Task.checkCancellation()

            let byteCount = outputByteCount(outputURL)
            if byteCount >= progressiveReadyByteCount {
                FFmpegProcessRegistry.shared.markExposed(outputPath: outputURL.path)
                return
            }

            if isCompletedCache(outputURL), byteCount > 0 {
                return
            }

            if !process.isRunning {
                if process.terminationStatus == 0, byteCount > 0 {
                    markCompletedCache(outputURL)
                    return
                }

                throw AttemptFailure(mode: mode, message: "FFmpeg ended before a playable fragment was ready.")
            }

            if waitedNanoseconds >= progressiveStartupTimeout, byteCount >= progressiveMinimumByteCount {
                FFmpegProcessRegistry.shared.markExposed(outputPath: outputURL.path)
                return
            }

            try await Task.sleep(nanoseconds: progressivePollInterval)
            waitedNanoseconds += progressivePollInterval
        }
    }

    private static func outputByteCount(_ outputURL: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        return attributes?[.size] as? UInt64 ?? 0
    }

    private static func isCompletedCache(_ outputURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: outputURL.path)
            && FileManager.default.fileExists(atPath: completionMarkerURL(for: outputURL).path)
    }

    private static func markCompletedCache(_ outputURL: URL) {
        FileManager.default.createFile(
            atPath: completionMarkerURL(for: outputURL).path,
            contents: Data(),
            attributes: nil
        )
    }

    private static func removeStaleCacheIfNeeded(_ outputURL: URL) throws {
        if FFmpegProcessRegistry.shared.process(for: outputURL.path) != nil {
            return
        }

        if FileManager.default.fileExists(atPath: outputURL.path), !isCompletedCache(outputURL) {
            try FileManager.default.removeItem(at: outputURL)
        }
    }

    private static func completionMarkerURL(for outputURL: URL) -> URL {
        outputURL.appendingPathExtension("complete")
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

    private static func preferredModes(forAudioCodec audioCodecName: String?) -> [Mode] {
        if let audioCodecName, isAVPlayerCandidateAudioCodec(audioCodecName) {
            return [.streamCopy, .audioAAC]
        }

        return [.audioAAC, .streamCopy]
    }

    private static func primaryVideoCodecName(inputURL: URL) async throws -> String? {
        try await primaryCodecName(inputURL: inputURL, streamSelector: "v:0")
    }

    private static func primaryAudioCodecName(inputURL: URL) async throws -> String? {
        try await primaryCodecName(inputURL: inputURL, streamSelector: "a:0")
    }

    private static func primaryCodecName(inputURL: URL, streamSelector: String) async throws -> String? {
        guard let ffprobeURL = FFmpegTool.ffprobeURL else {
            return nil
        }

        let output = try await runForOutput(
            executableURL: ffprobeURL,
            arguments: [
                "-v", "error",
                "-select_streams", streamSelector,
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

    private static func isAVPlayerCandidateAudioCodec(_ codecName: String) -> Bool {
        [
            "aac",
            "alac",
            "mp3",
            "ac3",
            "eac3"
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

final class FFmpegProcessRegistry: @unchecked Sendable {
    static let shared = FFmpegProcessRegistry()

    private let lock = NSLock()
    private var processesByOutputPath: [String: Process] = [:]
    private var exposedOutputPaths = Set<String>()

    private init() {}

    func process(for outputPath: String) -> Process? {
        lock.lock()
        defer { lock.unlock() }
        return processesByOutputPath[outputPath]
    }

    func set(_ process: Process, for outputPath: String) {
        lock.lock()
        defer { lock.unlock() }
        processesByOutputPath[outputPath] = process
    }

    func remove(for outputPath: String) {
        lock.lock()
        defer { lock.unlock() }
        processesByOutputPath.removeValue(forKey: outputPath)
        exposedOutputPaths.remove(outputPath)
    }

    func markExposed(outputPath: String) {
        lock.lock()
        defer { lock.unlock() }
        exposedOutputPaths.insert(outputPath)
    }

    func isExposed(outputPath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return exposedOutputPaths.contains(outputPath)
    }
}
