import Foundation
import GlazeCore

/// Reads the media container rather than the active playback engine.
///
/// VLC is the reference engine for formats such as MKV, so AVFoundation cannot be
/// the source of truth for the Info panel. ffprobe is already bundled for embedded
/// subtitle discovery and gives both playback paths the same, complete inspection.
struct MediaProbeResult: Sendable {
    let inspection: MediaInspection
    let spokenLanguageCode: String?
    let subtitleTracks: [EmbeddedSubtitleTrack]
}

/// Shares one container read between the Info and Subtitle panels. Remote media used
/// to launch three ffprobe processes for the same URL, competing with VLC for the first
/// bytes of the film.
actor MediaProbeCoordinator {
    static let shared = MediaProbeCoordinator()

    private let inspector = FFprobeMediaInspector()
    /// Probes still running, so a second panel joins the first rather than starting
    /// its own ffprobe.
    private var tasks: [String: Task<MediaProbeResult, Error>] = [:]
    /// Finished probes, kept only long enough for the panels of the film being watched
    /// to agree. Holding every result for the life of the process would both grow
    /// without bound and keep answering with a container the file no longer has.
    private var recentResults: [(key: String, result: MediaProbeResult)] = []
    private let recentResultLimit = 4

    func probe(url: URL, deferForPlayback: Bool) async throws -> MediaProbeResult {
        let key = url.absoluteString
        if let cached = recentResults.first(where: { $0.key == key })?.result {
            return cached
        }
        if let task = tasks[key] {
            return try await task.value
        }

        let inspector = inspector
        let task = Task<MediaProbeResult, Error> {
            if deferForPlayback {
                try await Task.sleep(for: .milliseconds(750))
            }
            return try await inspector.probe(url: url)
        }
        tasks[key] = task
        do {
            let result = try await task.value
            release(key: key, task: task)
            remember(result, for: key)
            return result
        } catch {
            release(key: key, task: task)
            throw error
        }
    }

    /// Drops the in-flight entry only when it is still the task this call started.
    /// Two callers failing on the same probe would otherwise let the second one evict
    /// a newer, still-running probe of the same film.
    private func release(key: String, task: Task<MediaProbeResult, Error>) {
        guard tasks[key] == task else { return }
        tasks.removeValue(forKey: key)
    }

    private func remember(_ result: MediaProbeResult, for key: String) {
        recentResults.removeAll { $0.key == key }
        recentResults.append((key: key, result: result))
        if recentResults.count > recentResultLimit {
            recentResults.removeFirst(recentResults.count - recentResultLimit)
        }
    }
}

actor FFprobeMediaInspector {
    enum InspectionError: Error {
        case toolUnavailable
        case probeFailed(String)
    }

    func inspect(url: URL) async throws -> MediaInspection {
        try await probe(url: url).inspection
    }

    func probe(url: URL) async throws -> MediaProbeResult {
        guard let ffprobeURL = FFmpegTool.ffprobeURL else {
            throw InspectionError.toolUnavailable
        }

        let data = try await run(
            executableURL: ffprobeURL,
            arguments: Self.networkTimeoutArguments(for: url) + [
                "-v", "error",
                "-show_entries",
                "format=format_name,duration,size,bit_rate:stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels,bit_rate:stream_tags=language,title:stream_disposition=default,forced",
                "-of", "json",
                url.isFileURL ? url.path : url.absoluteString
            ],
            deadline: MediaCachingPolicy.isRemote(url) ? 20 : 10
        )
        let response = try JSONDecoder().decode(ProbeResponse.self, from: data)
        let video = response.streams.first { $0.codecType == "video" }

        let inspection = MediaInspection(
            fileName: url.lastPathComponent,
            containerHint: displayContainer(response.format?.formatName, fallback: url.pathExtension),
            duration: formatDuration(response.format?.duration),
            fileSize: formatFileSize(response.format?.size),
            bitRate: formatBitRate(response.format?.bitRate),
            resolution: resolution(video),
            isPlayable: nil,
            tracks: response.streams.map(makeTrack),
            errorMessage: nil
        )
        let audioLanguage = response.streams
            .first { $0.codecType == "audio" }
            .flatMap { SubtitleLanguageCode.normalized($0.tags?.language) }
        let subtitleTracks = response.streams.compactMap { stream -> EmbeddedSubtitleTrack? in
            guard stream.codecType == "subtitle" else { return nil }
            return EmbeddedSubtitleTrack(
                streamIndex: stream.index,
                codec: stream.codecName ?? "unknown",
                languageCode: stream.tags?.language,
                title: stream.tags?.title,
                isDefault: stream.disposition?.defaultValue == 1,
                isForced: stream.disposition?.forced == 1
            )
        }
        return MediaProbeResult(
            inspection: inspection,
            spokenLanguageCode: audioLanguage,
            subtitleTracks: subtitleTracks
        )
    }

    private func makeTrack(_ stream: ProbeStream) -> MediaTrackInspection {
        var details: [String] = []
        if stream.codecType == "video" {
            if let width = stream.width, let height = stream.height { details.append("\(width)×\(height)") }
            if let fps = frameRate(stream.frameRate) { details.append(String(format: "%.2f fps", fps)) }
        } else if stream.codecType == "audio" {
            if let channels = stream.channels { details.append("\(channels) ch") }
            if let sampleRate = Int(stream.sampleRate ?? ""), sampleRate > 0 {
                details.append(String(format: "%.1f kHz", Double(sampleRate) / 1_000))
            }
        }
        if let language = normalizedTag(stream.tags?.language) { details.append(language.uppercased()) }
        if let title = normalizedTag(stream.tags?.title) { details.append(title) }
        if let rate = formatBitRate(stream.bitRate) { details.append(rate) }

        return MediaTrackInspection(
            title: trackTitle(stream.codecType),
            codec: (stream.codecName ?? "-").uppercased(),
            detail: details.isEmpty ? "–" : details.joined(separator: " · ")
        )
    }

    private func displayContainer(_ rawValue: String?, fallback: String) -> String {
        let names = rawValue?.split(separator: ",").map(String.init) ?? []
        let preferred = names.first(where: { $0 != "matroska" }) ?? names.first
        let value = preferred ?? fallback
        return value.isEmpty ? "–" : value.uppercased()
    }

    private func formatDuration(_ rawValue: String?) -> String {
        guard let value = Double(rawValue ?? ""), value.isFinite, value > 0 else { return "–" }
        let seconds = Int(value.rounded())
        return seconds >= 3_600
            ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func formatFileSize(_ rawValue: String?) -> String? {
        guard let value = Int64(rawValue ?? ""), value > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func formatBitRate(_ rawValue: String?) -> String? {
        guard let value = Double(rawValue ?? ""), value > 0 else { return nil }
        return value >= 1_000_000
            ? String(format: "%.1f Mbps", value / 1_000_000)
            : String(format: "%.0f kbps", value / 1_000)
    }

    private func resolution(_ stream: ProbeStream?) -> String? {
        guard let width = stream?.width, let height = stream?.height else { return nil }
        return "\(width) × \(height)"
    }

    private func frameRate(_ rawValue: String?) -> Double? {
        guard let rawValue else { return nil }
        let parts = rawValue.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return Double(rawValue) }
        return parts[0] / parts[1]
    }

    private func normalizedTag(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func trackTitle(_ type: String?) -> String {
        switch type {
        case "video": "Video"
        case "audio": "Audio"
        case "subtitle": "Subtitle"
        default: "Other"
        }
    }

    /// Tells ffmpeg to give up on a stalled read rather than wait forever.
    ///
    /// A NAS that stops answering mid-read leaves ffprobe blocked on the socket, and
    /// nothing above it ever hears back: the Info panel spins and the process stays.
    /// `rw_timeout` is in microseconds and applies per read.
    static func networkTimeoutArguments(for url: URL) -> [String] {
        guard MediaCachingPolicy.isRemote(url) else { return [] }
        return ["-rw_timeout", "8000000"]
    }

    /// - Parameter deadline: seconds to wait before killing the probe. ffmpeg's own
    ///   timeout covers a stalled socket; this covers everything else, including a
    ///   server that answers slowly enough to never finish.
    private func run(
        executableURL: URL,
        arguments: [String],
        deadline: TimeInterval
    ) async throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors

        let watchdog = Task {
            try await Task.sleep(for: .seconds(deadline))
            if process.isRunning { process.terminate() }
        }
        defer { watchdog.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let message = String(data: errorData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: InspectionError.probeFailed(message))
                }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: InspectionError.probeFailed(error.localizedDescription)) }
        }
    }
}

private extension FFprobeMediaInspector {
    struct ProbeResponse: Decodable {
        let streams: [ProbeStream]
        let format: ProbeFormat?
    }

    struct ProbeFormat: Decodable {
        let formatName: String?
        let duration: String?
        let size: String?
        let bitRate: String?

        enum CodingKeys: String, CodingKey {
            case formatName = "format_name"
            case duration, size
            case bitRate = "bit_rate"
        }
    }

    struct ProbeStream: Decodable {
        let index: Int
        let codecType: String?
        let codecName: String?
        let width: Int?
        let height: Int?
        let frameRate: String?
        let sampleRate: String?
        let channels: Int?
        let bitRate: String?
        let tags: ProbeTags?
        let disposition: ProbeDisposition?

        enum CodingKeys: String, CodingKey {
            case index, width, height, channels, tags, disposition
            case codecType = "codec_type"
            case codecName = "codec_name"
            case frameRate = "r_frame_rate"
            case sampleRate = "sample_rate"
            case bitRate = "bit_rate"
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
