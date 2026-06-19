import AVFoundation
import CoreMedia
import Foundation

struct MediaInspection {
    let fileName: String
    let containerHint: String
    let duration: String
    let isPlayable: Bool?
    let tracks: [MediaTrackInspection]
    let errorMessage: String?
}

struct MediaTrackInspection: Identifiable {
    let id = UUID()
    let title: String
    let codec: String
    let detail: String
}

enum MediaInspector {
    static func inspect(url: URL) async -> MediaInspection {
        let asset = AVURLAsset(url: url)

        do {
            async let duration = asset.load(.duration)
            async let isPlayable = asset.load(.isPlayable)
            async let tracks = asset.load(.tracks)

            let loadedDuration = try await duration
            let loadedTracks = try await tracks
            let inspectedTracks = await loadedTracks.asyncMap { track in
                await inspect(track: track)
            }

            return MediaInspection(
                fileName: url.lastPathComponent,
                containerHint: url.pathExtension.uppercased(),
                duration: formatDuration(loadedDuration),
                isPlayable: try await isPlayable,
                tracks: inspectedTracks,
                errorMessage: nil
            )
        } catch {
            return MediaInspection(
                fileName: url.lastPathComponent,
                containerHint: url.pathExtension.uppercased(),
                duration: "-",
                isPlayable: nil,
                tracks: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func inspect(track: AVAssetTrack) async -> MediaTrackInspection {
        do {
            let loadedMediaType = track.mediaType
            let loadedDescriptions = try await track.load(.formatDescriptions)
            let naturalSize = try await track.load(.naturalSize)
            let nominalFrameRate = try await track.load(.nominalFrameRate)
            let estimatedDataRate = try await track.load(.estimatedDataRate)
            let languageCode = try await track.load(.languageCode)
            let codec = loadedDescriptions.first.map(codecName(for:)) ?? "-"
            let detail = detailText(
                mediaType: loadedMediaType,
                naturalSize: naturalSize,
                nominalFrameRate: nominalFrameRate,
                estimatedDataRate: estimatedDataRate,
                languageCode: languageCode,
                formatDescriptions: loadedDescriptions
            )

            return MediaTrackInspection(
                title: title(for: loadedMediaType),
                codec: codec,
                detail: detail
            )
        } catch {
            return MediaTrackInspection(
                title: "Unknown",
                codec: "-",
                detail: error.localizedDescription
            )
        }
    }

    private static func detailText(
        mediaType: AVMediaType,
        naturalSize: CGSize,
        nominalFrameRate: Float,
        estimatedDataRate: Float,
        languageCode: String?,
        formatDescriptions: [CMFormatDescription]
    ) -> String {
        var parts: [String] = []

        if mediaType == .video {
            if naturalSize.width > 0, naturalSize.height > 0 {
                parts.append("\(Int(naturalSize.width))x\(Int(naturalSize.height))")
            }

            if nominalFrameRate > 0 {
                parts.append(String(format: "%.2f fps", nominalFrameRate))
            }
        }

        if mediaType == .audio, let description = formatDescriptions.first,
           let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
            let channels = streamDescription.pointee.mChannelsPerFrame
            if channels > 0 {
                parts.append("\(channels) ch")
            }
        }

        if estimatedDataRate > 0 {
            parts.append(String(format: "%.1f Mbps", estimatedDataRate / 1_000_000))
        }

        if let language = languageCode, !language.isEmpty {
            parts.append(language)
        }

        return parts.isEmpty ? "-" : parts.joined(separator: " / ")
    }

    private static func title(for mediaType: AVMediaType) -> String {
        switch mediaType {
        case .video:
            "Video"
        case .audio:
            "Audio"
        case .subtitle:
            "Subtitle"
        case .text:
            "Text"
        case .closedCaption:
            "Closed Caption"
        default:
            mediaType.rawValue
        }
    }

    private static func codecName(for formatDescription: CMFormatDescription) -> String {
        fourCharacterCode(CMFormatDescriptionGetMediaSubType(formatDescription))
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]

        if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }),
           let value = String(bytes: bytes, encoding: .macOSRoman) {
            return value
        }

        return String(format: "0x%08X", code)
    }

    private static func formatDuration(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else {
            return "-"
        }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var values: [T] = []
        for element in self {
            let value = await transform(element)
            values.append(value)
        }
        return values
    }
}
