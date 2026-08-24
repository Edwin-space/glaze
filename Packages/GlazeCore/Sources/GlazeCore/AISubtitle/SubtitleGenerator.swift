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

    /// The bundled ffmpeg, used to pull the audio out of the video.
    ///
    /// This used to go through AVFoundation, which cannot open Matroska at all — the
    /// container most of what people watch arrives in, and the reason the app ships VLC
    /// in the first place. Generating subtitles for any `.mkv` failed with "audio
    /// extraction failed" and no way to tell why. The bundled ffmpeg reads everything
    /// the player can play, which is the only sensible bar.
    private let ffmpegURL: URL?

    public init(modelTier: TranscriptionModelTier = .default, ffmpegURL: URL?) {
        self.modelTier = modelTier
        self.ffmpegURL = ffmpegURL
    }

    /// - Returns: the cues, plus how long the run took so tiers can be compared.
    /// - Parameter spokenLanguageCode: what the film is spoken in, when the container
    ///   says so. Worth passing whenever it is known: left to detect the language
    ///   itself, Whisper gets it wrong on material it has heard less of, and the
    ///   failure is silent. A Japanese film came back as fluent English — not a
    ///   translation anyone asked for, and no sign on screen that anything was amiss.
    public func generate(
        from videoURL: URL,
        spokenLanguageCode: String? = nil,
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
                decodeOptions: DecodingOptions(
                    language: SubtitleLanguageCode.normalized(spokenLanguageCode),
                    skipSpecialTokens: true
                )
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
        guard let ffmpegURL, FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else {
            throw GenerationError.audioExtractionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        // 16 kHz mono is the shape Whisper works in. Asking ffmpeg for it means the
        // resampling happens once, in C, rather than per chunk inside WhisperKit.
        let arguments = [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", videoURL.path,
            "-vn", "-sn", "-dn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            outputURL.path
        ]

        let failure = try await runFFmpeg(ffmpegURL, arguments)

        if let failure {
            try? FileManager.default.removeItem(at: outputURL)
            // ffmpeg says this when the film has no sound at all, which is worth
            // telling the viewer apart from a tool that would not run.
            throw failure.contains("does not contain any stream")
                ? GenerationError.noAudioTrack
                : GenerationError.audioExtractionFailed
        }

        return outputURL
    }

    /// - Returns: ffmpeg's stderr when it failed, nil when it succeeded.
    private func runFFmpeg(_ executableURL: URL, _ arguments: [String]) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let errorText = String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                continuation.resume(returning: process.terminationStatus == 0 ? nil : errorText)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GenerationError.audioExtractionFailed)
            }
        }
    }
}
