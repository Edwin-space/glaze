import Foundation
import GlazeCore

/// Reads the media container rather than the active playback engine.
///
/// VLC is the reference engine for formats such as MKV, so AVFoundation cannot be
/// the source of truth for the Info panel. ffprobe is already bundled for embedded
/// subtitle discovery and gives both playback paths the same, complete inspection.
actor FFprobeMediaInspector {
    enum InspectionError: Error {
        case toolUnavailable
        case probeFailed(String)
    }

    func inspect(url: URL) async throws -> MediaInspection {
        guard let ffprobeURL = FFmpegTool.ffprobeURL else {
            throw InspectionError.toolUnavailable
        }

        let data = try await run(
            executableURL: ffprobeURL,
            arguments: [
                "-v", "error",
                "-show_entries",
                "format=format_name,duration,size,bit_rate:stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels,bit_rate:stream_tags=language,title",
                "-of", "json",
                url.isFileURL ? url.path : url.absoluteString
            ]
        )
        let response = try JSONDecoder().decode(ProbeResponse.self, from: data)
        let video = response.streams.first { $0.codecType == "video" }

        return MediaInspection(
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

    private func run(executableURL: URL, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
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

        enum CodingKeys: String, CodingKey {
            case index, width, height, channels, tags
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
}
