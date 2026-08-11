import Foundation
import GlazeCore
import Observation

@MainActor
@Observable
final class SubtitleController {
    var detectedSubtitles: [SubtitleFile] = []
    var embeddedSubtitleTracks: [EmbeddedSubtitleTrack] = []
    var subtitleCues: [SubtitleCue] = []
    var activeSubtitleText = ""
    var isSubtitleVisible = true
    var selectedSubtitleName: String?
    var selectedSubtitlePath: String?
    var selectedEmbeddedTrackID: String?
    var status: SubtitleStatus = .noVideo
    var errorMessage: String?
    var isInspectingEmbeddedSubtitles = false
    var subtitlePreparationPlan: SubtitlePreparationPlan?
    var pendingTranslationRequest: SubtitleTranslationRequest?

    var isGenerating = false
    var generationStage: SubtitleGenerator.Stage?
    var generationProgress: Double = 0
    /// Fired after a generated subtitle is saved, loaded, and attached — so the view can update the media asset.
    var onGenerationFinished: (() -> Void)?
    var onEmbeddedSubtitleLoaded: (() -> Void)?

    private var generationTask: Task<Void, Never>?
    private var embeddedSubtitleTask: Task<Void, Never>?
    private let embeddedSubtitleService = EmbeddedSubtitleService()

    /// Resets subtitle state for a newly loaded video and auto-loads the best sidecar match, if any.
    func prepareForNewVideo(url: URL) {
        embeddedSubtitleTask?.cancel()
        detectedSubtitles = SubtitleSidecarDetector.detect(for: url)
        embeddedSubtitleTracks = []
        subtitleCues = []
        activeSubtitleText = ""
        isSubtitleVisible = true
        selectedSubtitleName = nil
        selectedSubtitlePath = nil
        selectedEmbeddedTrackID = nil
        errorMessage = nil
        isInspectingEmbeddedSubtitles = true
        subtitlePreparationPlan = nil
        pendingTranslationRequest = nil
        loadPreferredIfAvailable()
        discoverEmbeddedSubtitles(in: url)
    }

    func loadEmbedded(_ track: EmbeddedSubtitleTrack, from videoURL: URL) {
        embeddedSubtitleTask?.cancel()
        embeddedSubtitleTask = Task {
            await extractAndLoadEmbedded(track, from: videoURL, translationTarget: nil)
        }
    }

    func updateActiveCue(at time: TimeInterval) {
        activeSubtitleText = subtitleCues.first { $0.contains(time) }?.text ?? ""
    }

    @discardableResult
    func importManual(url: URL) -> SubtitleFile {
        let subtitle = SubtitleFile.manual(url: url)

        if !detectedSubtitles.contains(where: { $0.url.path == subtitle.url.path }) {
            detectedSubtitles.append(subtitle)
        }

        load(subtitle)
        errorMessage = nil
        return subtitle
    }

    func load(_ subtitle: SubtitleFile) {
        do {
            subtitleCues = try SubtitleParser.parse(url: subtitle.url)
            selectedSubtitleName = subtitle.displayName
            selectedSubtitlePath = subtitle.url.path
            selectedEmbeddedTrackID = nil
            activeSubtitleText = ""
            isSubtitleVisible = true
            status = computeStatus(for: detectedSubtitles)
            errorMessage = nil
        } catch {
            subtitleCues = []
            selectedSubtitleName = nil
            selectedSubtitlePath = nil
            selectedEmbeddedTrackID = nil
            activeSubtitleText = ""
            status = computeStatus(for: detectedSubtitles)
            errorMessage = subtitleErrorMessage(for: error)
        }
    }

    /// Starts on-device AI subtitle generation for the given video. No-op if a generation is already running.
    func startGenerating(from videoURL: URL) {
        guard !isGenerating else {
            return
        }

        isGenerating = true
        generationStage = .extractingAudio
        generationProgress = 0
        status = .generating
        errorMessage = nil

        generationTask = Task {
            let generator = SubtitleGenerator()
            do {
                let cues = try await generator.generate(from: videoURL) { [weak self] progress in
                    Task { @MainActor in
                        self?.generationStage = progress.stage
                        self?.generationProgress = progress.fraction
                    }
                }
                guard !Task.isCancelled else {
                    return
                }
                finishGenerating(cues: cues, videoURL: videoURL)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                isGenerating = false
                status = computeStatus(for: detectedSubtitles)
                errorMessage = generationErrorMessage(for: error)
            }
            generationTask = nil
        }
    }

    func cancelGenerating() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        status = computeStatus(for: detectedSubtitles)
    }

    private func discoverEmbeddedSubtitles(in videoURL: URL) {
        let preferredLanguages = Locale.preferredLanguages
        embeddedSubtitleTask = Task {
            do {
                let tracks = try await embeddedSubtitleService.discoverTracks(in: videoURL)
                guard !Task.isCancelled else { return }
                embeddedSubtitleTracks = tracks
                isInspectingEmbeddedSubtitles = false

                guard !tracks.isEmpty else {
                    status = computeStatus(for: detectedSubtitles)
                    return
                }

                let plan = SubtitlePreparationPlanner.plan(
                    embeddedTracks: tracks,
                    preferredLanguageCodes: preferredLanguages
                )
                subtitlePreparationPlan = plan
                status = computeStatus(for: detectedSubtitles)

                guard subtitleCues.isEmpty,
                      let track = plan.selectedTrack,
                      track.canProvideTimedText else {
                    return
                }

                let translationTarget: String?
                if case .translateEmbedded(_, let targetLanguageCode) = plan {
                    translationTarget = targetLanguageCode
                } else {
                    translationTarget = nil
                }

                await extractAndLoadEmbedded(
                    track,
                    from: videoURL,
                    translationTarget: translationTarget
                )
            } catch is CancellationError {
                return
            } catch EmbeddedSubtitleService.ServiceError.toolUnavailable {
                isInspectingEmbeddedSubtitles = false
                status = computeStatus(for: detectedSubtitles)
            } catch {
                isInspectingEmbeddedSubtitles = false
                status = computeStatus(for: detectedSubtitles)
                errorMessage = L10n.string("subtitle.error.embedded_inspection_failed")
            }
        }
    }

    private func extractAndLoadEmbedded(
        _ track: EmbeddedSubtitleTrack,
        from videoURL: URL,
        translationTarget: String?
    ) async {
        do {
            let extractedURL = try await embeddedSubtitleService.extract(track: track, from: videoURL)
            guard !Task.isCancelled else { return }
            let subtitle = SubtitleFile.manual(url: extractedURL)
            if !detectedSubtitles.contains(where: { $0.url.path == subtitle.url.path }) {
                detectedSubtitles.append(subtitle)
            }
            load(subtitle)
            selectedEmbeddedTrackID = track.id
            onEmbeddedSubtitleLoaded?()

            if let translationTarget {
                pendingTranslationRequest = SubtitleTranslationRequest(
                    sourceTrack: track,
                    targetLanguageCode: translationTarget,
                    cues: subtitleCues
                )
            } else {
                pendingTranslationRequest = nil
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = L10n.string("subtitle.error.embedded_extraction_failed")
        }
    }

    private func finishGenerating(cues: [SubtitleCue], videoURL: URL) {
        isGenerating = false

        let outputURL = Self.generatedSubtitleURL(for: videoURL)
        do {
            try SubtitleWriter.writeSRT(cues: cues, to: outputURL)
            let subtitle = SubtitleFile.manual(url: outputURL)

            if !detectedSubtitles.contains(where: { $0.url.path == subtitle.url.path }) {
                detectedSubtitles.append(subtitle)
            }

            load(subtitle)
            onGenerationFinished?()
        } catch {
            status = computeStatus(for: detectedSubtitles)
            errorMessage = L10n.string("subtitle.error.save_failed")
        }
    }

    private func generationErrorMessage(for error: Error) -> String {
        guard let generationError = error as? SubtitleGenerator.GenerationError else {
            return L10n.string("subtitle.error.generation_failed")
        }

        switch generationError {
        case .noAudioTrack:
            return L10n.string("subtitle.error.no_audio_track")
        case .audioExtractionFailed:
            return L10n.string("subtitle.error.audio_extraction_failed")
        case .modelUnavailable:
            return L10n.string("subtitle.error.model_unavailable")
        case .transcriptionFailed:
            return L10n.string("subtitle.error.generation_failed")
        }
    }

    /// Generated subtitles are stored app-internally (not next to the source video) — matches the
    /// "앱 내부 저장" default policy in `03_ai_subtitle_workflow.md`. A storage-location prompt is a follow-up.
    private static func generatedSubtitleURL(for videoURL: URL) -> URL {
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return supportDirectory
            .appendingPathComponent("Glaze", isDirectory: true)
            .appendingPathComponent("Subtitles", isDirectory: true)
            .appendingPathComponent("\(baseName).original.srt")
    }

    func kindLabel(for kind: SubtitleFile.Kind) -> String {
        switch kind {
        case .korean:
            L10n.string("subtitle.kind.korean")
        case .original:
            L10n.string("subtitle.kind.original")
        case .unknown:
            L10n.string("subtitle.kind.unknown")
        }
    }

    func statusHint(hasPlayer: Bool) -> String {
        guard hasPlayer else {
            return L10n.string("subtitle.status.hint")
        }

        if let selectedSubtitleName {
            if !isSubtitleVisible, !subtitleCues.isEmpty {
                return String(format: L10n.string("subtitle.status.hidden_hint_format"), selectedSubtitleName)
            }

            if case .translateEmbedded(_, let targetLanguageCode) = subtitlePreparationPlan,
               pendingTranslationRequest != nil {
                return String(
                    format: L10n.string("subtitle.status.embedded_translation_ready_format"),
                    targetLanguageCode.uppercased()
                )
            }

            return String(format: L10n.string("subtitle.status.loaded_hint_format"), selectedSubtitleName)
        }

        guard !detectedSubtitles.isEmpty || !embeddedSubtitleTracks.isEmpty else {
            return L10n.string("subtitle.status.generate_or_import_hint")
        }

        let names = (
            detectedSubtitles.map(\.displayName)
                + embeddedSubtitleTracks.map(embeddedTrackLabel)
        ).joined(separator: ", ")
        return String(format: L10n.string("subtitle.status.detected_hint_format"), names)
    }

    var panelOutputValue: String {
        guard !detectedSubtitles.isEmpty else {
            return L10n.string("subtitle.panel.output_dual")
        }

        let hasKorean = detectedSubtitles.contains { $0.kind == .korean }
        return hasKorean ? L10n.string("subtitle.panel.output_korean_available") : L10n.string("subtitle.panel.output_original_available")
    }

    private func loadPreferredIfAvailable() {
        guard let preferredSubtitle = detectedSubtitles.sorted(by: preferredSubtitleSort).first else {
            status = computeStatus(for: detectedSubtitles)
            return
        }

        load(preferredSubtitle)
    }

    private func preferredSubtitleSort(_ lhs: SubtitleFile, _ rhs: SubtitleFile) -> Bool {
        priority(for: lhs.kind) < priority(for: rhs.kind)
    }

    private func priority(for kind: SubtitleFile.Kind) -> Int {
        switch kind {
        case .korean:
            0
        case .original:
            1
        case .unknown:
            2
        }
    }

    private func computeStatus(for subtitles: [SubtitleFile]) -> SubtitleStatus {
        if !subtitleCues.isEmpty {
            return .subtitleLoaded
        }

        guard !subtitles.isEmpty || !embeddedSubtitleTracks.isEmpty else {
            return .readyToGenerate
        }

        if subtitles.contains(where: { $0.kind == .korean }) {
            return .koreanSubtitleDetected
        }

        return .subtitleDetected
    }

    func embeddedTrackLabel(_ track: EmbeddedSubtitleTrack) -> String {
        if let title = track.title {
            return title
        }
        if let languageCode = track.languageCode {
            return String(
                format: L10n.string("subtitle.embedded.language_format"),
                languageCode.uppercased()
            )
        }
        return String(
            format: L10n.string("subtitle.embedded.track_format"),
            track.streamIndex
        )
    }

    private func subtitleErrorMessage(for error: Error) -> String {
        guard let parseError = error as? SubtitleParser.ParseError else {
            return L10n.string("subtitle.error.read_failed")
        }

        switch parseError {
        case .unsupportedFormat:
            return L10n.string("subtitle.error.unsupported_format")
        case .unreadableFile:
            return L10n.string("subtitle.error.read_failed")
        case .emptySubtitle:
            return L10n.string("subtitle.error.empty_file")
        }
    }
}
