import AVFoundation
import Foundation
import WhisperKit

/// Generates subtitle cues for a single video by running on-device Whisper (via WhisperKit) over its audio track.
/// Cross-platform (no AppKit/AVKit dependency), so it can be shared with a future iOS target.
public final class SubtitleGenerator {
    public enum Stage: Sendable {
        case extractingAudio
        case preparingModel
        case transcribing
    }

    public struct Progress: Sendable {
        public let stage: Stage
        public let fraction: Double

        public init(stage: Stage, fraction: Double) {
            self.stage = stage
            self.fraction = fraction
        }
    }

    public enum GenerationError: Error, Sendable {
        case noAudioTrack
        case audioExtractionFailed
        case modelUnavailable
        case transcriptionFailed
    }

    /// Which Whisper model to run. Set at init so a run cannot change model midway.
    public let modelTier: TranscriptionModelTier

    public init(modelTier: TranscriptionModelTier = .default) {
        self.modelTier = modelTier
    }

    /// - Returns: the cues, plus how long the run took so tiers can be compared.
    public func generate(
        from videoURL: URL,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> (cues: [SubtitleCue], duration: TimeInterval, languageCode: String?) {
        let startedAt = Date()
        onProgress(Progress(stage: .extractingAudio, fraction: 0))
        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        onProgress(Progress(stage: .preparingModel, fraction: 0))
        let whisperKit: WhisperKit
        do {
            whisperKit = try await WhisperKit(WhisperKitConfig(model: modelTier.whisperModelName))
        } catch {
            throw GenerationError.modelUnavailable
        }

        whisperKit.transcriptionStateCallback = { state in
            switch state {
            case .convertingAudio:
                onProgress(Progress(stage: .preparingModel, fraction: 1))
            case .transcribing:
                onProgress(Progress(stage: .transcribing, fraction: 0))
            case .finished:
                onProgress(Progress(stage: .transcribing, fraction: 1))
            }
        }

        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: DecodingOptions(skipSpecialTokens: true)
            )
        } catch {
            throw GenerationError.transcriptionFailed
        }

        let cues = results
            .flatMap(\.segments)
            .map { segment in
                SubtitleCue(
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty }

        guard !cues.isEmpty else {
            throw GenerationError.transcriptionFailed
        }

        // Whisper reports what it heard. Without it the app cannot tell a Korean film
        // transcribed for a Korean viewer from one that still needs translating.
        let spokenLanguage = SubtitleLanguageCode.normalized(results.first?.language)

        return (cues, Date().timeIntervalSince(startedAt), spokenLanguage)
    }

    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw GenerationError.audioExtractionFailed
        }

        guard !audioTracks.isEmpty else {
            throw GenerationError.noAudioTrack
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw GenerationError.audioExtractionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        do {
            try await exportSession.export(to: outputURL, as: .m4a)
        } catch {
            throw GenerationError.audioExtractionFailed
        }

        return outputURL
    }
}
