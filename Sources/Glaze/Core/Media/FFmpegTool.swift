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
    enum RemuxError: Error {
        case toolUnavailable
        case failed(String)
    }

    static func remuxForAVPlayer(inputURL: URL) async throws -> URL {
        guard let ffmpegURL = FFmpegTool.ffmpegURL else {
            throw RemuxError.toolUnavailable
        }

        let outputURL = try outputURL(for: inputURL)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let arguments = [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c", "copy",
            "-movflags", "+faststart",
            outputURL.path
        ]

        try await run(ffmpegURL: ffmpegURL, arguments: arguments)
        return outputURL
    }

    private static func run(ffmpegURL: URL, arguments: [String]) async throws {
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
                    continuation.resume(throwing: RemuxError.failed(errorText))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func outputURL(for inputURL: URL) throws -> URL {
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
        return cacheRoot.appendingPathComponent("\(baseName)-\(hash).mp4")
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
