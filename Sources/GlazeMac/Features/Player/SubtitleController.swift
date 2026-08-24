import Foundation
import GlazeCore
import Observation
import Translation

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

    /// What the container says the film is spoken in. nil when it says nothing, and
    /// transcription falls back to letting Whisper decide.
    private(set) var spokenLanguageCode: String?

    var isGenerating = false
    var generationStage: SubtitleGenerator.Stage?
    var generationProgress: Double = 0

    /// Settings that outlive a video live in `GlazePreferences`, so the Settings
    /// window and this panel edit the same values instead of each holding a copy.
    private let preferences: GlazePreferences

    var transcriptionTier: TranscriptionModelTier {
        get { preferences.transcriptionTier }
        set { preferences.transcriptionTier = newValue }
    }
    var translationQuality: SubtitleTranslationQuality {
        get { preferences.translationQuality }
        set { preferences.translationQuality = newValue }
    }
    var translationEngineID: SubtitleTranslationEngineID {
        get { preferences.translationEngineID }
        set { preferences.translationEngineID = newValue }
    }
    var storageLocation: SubtitleStorageLocation {
        get { preferences.storageLocation }
        set { preferences.storageLocation = newValue }
    }
    /// The resource currently loaded, so subtitles are keyed on what is playing rather
    /// than on a local path a streamed video does not have.
    var currentResource: MediaResource?

    /// Wall-clock cost of the last run of each stage, so tiers can be compared on
    /// something measured rather than remembered.
    var lastGenerationDuration: TimeInterval?
    var lastTranslationDuration: TimeInterval?

    var isTranslating = false
    var translationProgress: Double = 0
    var translationOutput: SubtitleTranslationOutput {
        get { preferences.translationOutput }
        set { preferences.translationOutput = newValue }
    }
    /// Set to start a translation. SwiftUI's `.translationTask` observes this and
    /// hands back a session, which is the only way to obtain one.
    var translationConfiguration: TranslationSession.Configuration?
    /// Fired after a generated subtitle is saved, loaded, and attached — so the view can update the media asset.
    var onGenerationFinished: (() -> Void)?
    var onEmbeddedSubtitleLoaded: (() -> Void)?

    private var generationTask: Task<Void, Never>?
    private var embeddedSubtitleTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private let embeddedSubtitleService = EmbeddedSubtitleService()
    private let subtitleStore: SubtitleStoring = FileSubtitleStore(
        libraryDirectory: SubtitleController.defaultLibraryDirectory
    )
    /// Video the pending translation belongs to, so a late result cannot be written
    /// against a file the user has already moved on from.
    private var translationVideoURL: URL?
    private var translationStartedAt: Date?

    init(preferences: GlazePreferences = .shared) {
        self.preferences = preferences
    }

    /// Resets subtitle state for a newly loaded video and auto-loads the best sidecar match, if any.
    func prepareForNewVideo(url: URL) {
        embeddedSubtitleTask?.cancel()
        cancelTranslating()
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
        spokenLanguageCode = nil
        loadPreferredIfAvailable()
        discoverEmbeddedSubtitles(in: url)
    }

    func loadEmbedded(_ track: EmbeddedSubtitleTrack, from videoURL: URL) {
        embeddedSubtitleTask?.cancel()
        embeddedSubtitleTask = Task {
            await extractAndLoadEmbedded(track, from: videoURL)
        }
    }

    /// The language the viewer reads, which is what anything else gets translated into.
    static var preferredTargetLanguageCode: String {
        Locale.preferredLanguages.compactMap(SubtitleLanguageCode.normalized).first ?? "en"
    }

    /// Decides whether the subtitle now loaded is worth offering to translate.
    ///
    /// Translation used to be offered only for subtitles extracted from the video
    /// container, so a `.srt` sitting next to the file — the ordinary case — could not be
    /// translated at all. The offer now follows the loaded subtitle rather than where it
    /// came from.
    private func offerTranslation(displayName: String, sourceLanguageCode: String?) {
        let target = Self.preferredTargetLanguageCode

        // Nothing to translate, or it already reads in the viewer's language.
        guard !subtitleCues.isEmpty, sourceLanguageCode != target else {
            pendingTranslationRequest = nil
            return
        }

        pendingTranslationRequest = SubtitleTranslationRequest(
            source: SubtitleTranslationSource(
                displayName: displayName,
                languageCode: sourceLanguageCode
            ),
            targetLanguageCode: target,
            cues: subtitleCues
        )
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

    /// - Parameters:
    ///   - sourceLanguageCode: what the subtitle is written in, when the caller knows —
    ///     an embedded track carries its own tag. Otherwise the file name is read.
    ///   - displayName: what to call this subtitle when offering to translate it.
    func load(
        _ subtitle: SubtitleFile,
        sourceLanguageCode: String? = nil,
        displayName: String? = nil
    ) {
        do {
            // The video is named so file access can be coordinated against it. This
            // does not yet unlock sidecar subtitles under the App Sandbox — see
            // RelatedFileAccess for what is still missing.
            subtitleCues = try SubtitleParser.parse(
                url: subtitle.url,
                relatedTo: currentResource?.localFileURL
            )
            selectedSubtitleName = subtitle.displayName
            selectedSubtitlePath = subtitle.url.path
            selectedEmbeddedTrackID = nil
            activeSubtitleText = ""
            isSubtitleVisible = true
            status = computeStatus(for: detectedSubtitles)
            errorMessage = nil
            offerTranslation(
                displayName: displayName ?? subtitle.displayName,
                sourceLanguageCode: sourceLanguageCode ?? subtitle.languageCode
            )
        } catch {
            subtitleCues = []
            selectedSubtitleName = nil
            selectedSubtitlePath = nil
            selectedEmbeddedTrackID = nil
            activeSubtitleText = ""
            status = computeStatus(for: detectedSubtitles)
            errorMessage = subtitleErrorMessage(for: error)
            pendingTranslationRequest = nil
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

        // Read while the video was opened. The tag is right far more often than
        // Whisper's own detection, and passing it also skips the detection pass.
        let spokenLanguage = spokenLanguageCode

        generationTask = Task { [transcriptionTier] in
            let generator = SubtitleGenerator(modelTier: transcriptionTier, ffmpegURL: FFmpegTool.ffmpegURL)
            do {
                let result = try await generator.generate(
                    from: videoURL,
                    spokenLanguageCode: spokenLanguage
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.generationStage = progress.stage
                        self?.generationProgress = progress.fraction
                    }
                }
                guard !Task.isCancelled else {
                    return
                }
                lastGenerationDuration = result.duration
                finishGenerating(
                    cues: result.cues,
                    videoURL: videoURL,
                    languageCode: result.languageCode
                )
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
            spokenLanguageCode = await embeddedSubtitleService.spokenLanguageCode(in: videoURL)
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

                await extractAndLoadEmbedded(track, from: videoURL)
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

    // MARK: - Translation

    /// True when there is a loaded subtitle in another language that we could turn
    /// into the viewer's language.
    var canTranslate: Bool {
        pendingTranslationRequest != nil && !subtitleCues.isEmpty && !isTranslating
    }

    var translationTargetLanguageCode: String? {
        pendingTranslationRequest?.targetLanguageCode
    }

    /// Arms the translation. The actual work starts when `.translationTask` responds
    /// to the configuration change by handing back a session.
    func startTranslating(for videoURL: URL) {
        guard let request = pendingTranslationRequest, !subtitleCues.isEmpty else { return }

        translationTask?.cancel()
        translationVideoURL = videoURL
        errorMessage = nil
        translationProgress = 0
        translationStartedAt = Date()
        isTranslating = true
        status = .translating

        // The on-device model needs no session from SwiftUI, so it runs straight from
        // here. Only the system translator has to go out through `.translationTask`.
        guard translationEngineID != .appleFoundationModel else {
            runOnDeviceModelTranslation()
            return
        }

        let source = request.source.languageCode.map(Locale.Language.init(identifier:))
        let target = Locale.Language(identifier: request.targetLanguageCode)
        // A fresh Configuration each run; reusing an equal one would not retrigger
        // the task, so a repeat translation would silently do nothing.
        if #available(macOS 26.4, *) {
            // Strategy is the system translator's only quality lever, and it only
            // exists from 26.4 — below that the system picks for us.
            let strategy: TranslationSession.Strategy = switch translationQuality {
            case .fast: .lowLatency
            case .highFidelity: .highFidelity
            }
            translationConfiguration = TranslationSession.Configuration(
                source: source,
                target: target,
                preferredStrategy: strategy
            )
        } else {
            translationConfiguration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    private func runOnDeviceModelTranslation() {
        guard let input = translationInput() else { return }

        translationTask = Task { [weak self] in
            guard let self else { return }
            let engine = FoundationModelTranslationEngine(
                targetLanguageDisplayName: input.targetLanguageDisplayName
            )
            do {
                let translations = try await engine.translate(
                    segments: input.segments,
                    targetLanguageCode: input.targetLanguageCode,
                    onProgress: { progress in
                        self.updateTranslationProgress(progress)
                    }
                )
                guard !Task.isCancelled else { return }
                applyTranslation(translations, for: input)
            } catch {
                guard !Task.isCancelled else { return }
                failTranslating(error)
            }
            translationTask = nil
        }
    }

    /// Why the on-device model cannot be used right now, if it cannot.
    var onDeviceModelUnavailableReason: String? {
        switch FoundationModelTranslationEngine.availability() {
        case .available:
            nil
        case .unavailable(.appleIntelligenceNotEnabled):
            L10n.string("subtitle.translate.engine.unavailable_not_enabled")
        case .unavailable(.deviceNotEligible):
            L10n.string("subtitle.translate.engine.unavailable_device")
        case .unavailable(.modelNotReady):
            L10n.string("subtitle.translate.engine.unavailable_not_ready")
        case .unavailable:
            L10n.string("subtitle.translate.engine.unavailable_generic")
        }
    }

    func cancelTranslating() {
        translationTask?.cancel()
        translationTask = nil
        translationConfiguration = nil
        translationVideoURL = nil
        isTranslating = false
        translationProgress = 0
        if status == .translating {
            status = computeStatus(for: detectedSubtitles)
        }
    }

    /// Everything the engine needs, in Sendable form — the session itself never
    /// crosses onto this actor.
    struct TranslationInput: Sendable {
        let cues: [SubtitleCue]
        /// Cues regrouped into sentences, so the engine never sees a bare fragment.
        let segments: [SubtitleSegment]
        let output: SubtitleTranslationOutput
        let targetLanguageCode: String
        /// The language named the way a person would say it, for the model's instructions.
        let targetLanguageDisplayName: String
        let engineID: SubtitleTranslationEngineID
        let videoURL: URL
    }

    /// Snapshot taken as a run begins; nil when there is nothing to translate.
    func translationInput() -> TranslationInput? {
        guard isTranslating,
              let videoURL = translationVideoURL,
              let targetLanguageCode = pendingTranslationRequest?.targetLanguageCode,
              !subtitleCues.isEmpty else {
            return nil
        }

        return TranslationInput(
            cues: subtitleCues,
            segments: SubtitleSegmenter.segments(from: subtitleCues),
            output: translationOutput,
            targetLanguageCode: targetLanguageCode,
            targetLanguageDisplayName: Locale.current
                .localizedString(forLanguageCode: targetLanguageCode) ?? targetLanguageCode,
            engineID: translationEngineID,
            videoURL: videoURL
        )
    }

    /// Reassembles engine output onto the original cue timings and saves the result.
    func applyTranslation(_ translations: [String?], for input: TranslationInput) {
        let cues = SubtitleTranslationAssembler.assemble(
            cues: input.cues,
            segments: input.segments,
            translations: translations,
            output: input.output
        )
        applyTranslation(cues: cues, videoURL: input.videoURL)
    }

    func updateTranslationProgress(_ progress: Double) {
        guard isTranslating else { return }
        translationProgress = progress
    }

    func applyTranslation(cues: [SubtitleCue], videoURL: URL) {
        // A result that arrived after the user moved on must not overwrite the new video.
        guard translationVideoURL == videoURL else { return }
        finishTranslating(cues: cues, videoURL: videoURL)
    }

    func failTranslating(_ error: Error) {
        if error is CancellationError {
            cancelTranslating()
            return
        }
        isTranslating = false
        translationConfiguration = nil
        status = computeStatus(for: detectedSubtitles)
        errorMessage = translationErrorMessage(for: error)
    }

    private func finishTranslating(cues: [SubtitleCue], videoURL: URL) {
        isTranslating = false
        translationConfiguration = nil
        if let translationStartedAt {
            lastTranslationDuration = Date().timeIntervalSince(translationStartedAt)
        }
        translationStartedAt = nil

        let languageCode = pendingTranslationRequest?.targetLanguageCode ?? "translated"

        do {
            let outputURL = try subtitleStore.save(
                cues: cues,
                for: currentResource ?? .localFile(videoURL),
                kind: .translated(languageCode: languageCode),
                preferring: storageLocation
            )
            let subtitle = SubtitleFile.manual(url: outputURL)

            if !detectedSubtitles.contains(where: { $0.url.path == subtitle.url.path }) {
                detectedSubtitles.append(subtitle)
            }

            // The file is named for the language it is in, so loading it clears the
            // offer that produced it.
            load(subtitle)
            onGenerationFinished?()
        } catch {
            status = computeStatus(for: detectedSubtitles)
            errorMessage = L10n.string("subtitle.error.save_failed")
        }
    }

    private func translationErrorMessage(for error: Error) -> String {
        if let translationError = error as? SubtitleTranslationError {
            switch translationError {
            case .languagePairUnavailable:
                return L10n.string("subtitle.error.translation_unavailable")
            case .translationFailed:
                return L10n.string("subtitle.error.translation_failed")
            }
        }
        return L10n.string("subtitle.error.translation_failed")
    }

    private func extractAndLoadEmbedded(
        _ track: EmbeddedSubtitleTrack,
        from videoURL: URL
    ) async {
        do {
            let extractedURL = try await embeddedSubtitleService.extract(track: track, from: videoURL)
            guard !Task.isCancelled else { return }
            let subtitle = SubtitleFile.manual(url: extractedURL)
            if !detectedSubtitles.contains(where: { $0.url.path == subtitle.url.path }) {
                detectedSubtitles.append(subtitle)
            }
            load(
                subtitle,
                sourceLanguageCode: track.languageCode,
                displayName: embeddedTrackLabel(track)
            )
            selectedEmbeddedTrackID = track.id
            onEmbeddedSubtitleLoaded?()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = L10n.string("subtitle.error.embedded_extraction_failed")
        }
    }

    private func finishGenerating(cues: [SubtitleCue], videoURL: URL, languageCode: String?) {
        isGenerating = false

        do {
            let outputURL = try subtitleStore.save(
                cues: cues,
                for: currentResource ?? .localFile(videoURL),
                kind: .generated,
                preferring: storageLocation
            )
            let subtitle = SubtitleFile.manual(url: outputURL)

            if !detectedSubtitles.contains(where: { $0.url.path == subtitle.url.path }) {
                detectedSubtitles.append(subtitle)
            }

            // The saved name carries no language tag, so pass what Whisper heard —
            // otherwise a Korean film would be offered for translation into Korean.
            load(
                subtitle,
                sourceLanguageCode: languageCode,
                displayName: L10n.string("subtitle.source.generated")
            )
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
    /// Where `appLibrary` storage lives, and the fallback when the video's own folder
    /// cannot be written to.
    static var defaultLibraryDirectory: URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return supportDirectory
            .appendingPathComponent("Glaze", isDirectory: true)
            .appendingPathComponent("Subtitles", isDirectory: true)
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

    /// What to show for "영상 언어": the language the container declares, or a note
    /// that Glaze will work it out from the audio.
    var panelSpokenLanguageValue: String {
        guard let spokenLanguageCode,
              let name = Locale.current.localizedString(forLanguageCode: spokenLanguageCode) else {
            return L10n.string("subtitle.panel.auto_detect")
        }

        return name
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
