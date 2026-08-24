import AVKit
import GlazeCore
import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

struct PlayerView: View {
    @State private var playback = PlaybackController()
    @State private var playlistStore = PlaylistStore()
    @State private var subtitles = SubtitleController()
    @State private var mediaAssets = MediaAssetStore()

    @State private var activePanel: PlayerPanel?
    @State private var isDropTargeted = false
    @State private var isNetworkBrowserPresented = false
    @State private var areControlsVisible = true
    @State private var isSeeking = false
    @State private var hideControlsTask: Task<Void, Never>?

    @Environment(\.controlActiveState) private var controlActiveState

    /// How long the controls linger after the pointer stops moving over the video.
    private static let controlsIdleDelay = Duration.seconds(2.5)
    /// Shorter grace period once the pointer has left the video entirely.
    private static let controlsExitDelay = Duration.milliseconds(400)

    var body: some View {
        videoStage
            .inspector(isPresented: inspectorPresentation) {
                playerInspector
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
            .toolbar { playerToolbar }
            // Let the backdrop run up under the title bar instead of stopping at
            // an opaque strip — without this the glass reads as a pasted-on panel.
            .toolbarBackground(.hidden, for: .windowToolbar)
            .sheet(isPresented: $isNetworkBrowserPresented) {
                NetworkMediaBrowserView(onOpen: openNetworkMedia)
            }
            // The only way to obtain a TranslationSession: SwiftUI vends one whenever
            // the configuration changes, which is what starts a translation run. The
            // session stays inside this closure — only Sendable data crosses to the
            // controller, since TranslationSession is a non-Sendable class.
            .translationTask(subtitles.translationConfiguration) { session in
                guard let input = subtitles.translationInput() else { return }
                await runTranslation(input: input, engine: AppleTranslationEngine(session: session))
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime), perform: handlePlaybackEnd)
            .onReceive(NotificationCenter.default.publisher(for: .openVideoCommand)) { _ in openVideo() }
            .onReceive(NotificationCenter.default.publisher(for: .openMediaURL)) { notification in
                guard let url = notification.object as? URL else { return }
                PendingOpenMediaURLs.consume(url)
                openMedia(from: url)
            }
            // How a file opened from Finder actually arrives. The app delegate declares
            // application(_:openFiles:), but under the SwiftUI App lifecycle AppKit never
            // calls it — opening a second video while Glaze was running did nothing.
            .onOpenURL { url in
                PendingOpenMediaURLs.consume(url)
                openMedia(from: url)
            }
            .onAppear {
                configureControllers()
                NativeVLCLibrary.prewarm()
                if let url = PendingOpenMediaURLs.consumeFirst() {
                    openMedia(from: url)
                }
            }
            .onDisappear {
                hideControlsTask?.cancel()
                playback.stopForWindowClose()
            }
    }

    private var inspectorPresentation: Binding<Bool> {
        Binding(
            get: { activePanel != nil },
            set: { isPresented in
                if !isPresented { activePanel = nil }
            }
        )
    }

    private var currentFileName: String {
        playback.currentVideoURL?.lastPathComponent ?? L10n.string("player.no_file")
    }

    @ToolbarContentBuilder
    private var playerToolbar: some ToolbarContent {
        if playback.currentVideoURL != nil {
            ToolbarItem(placement: .principal) {
                Text(currentFileName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 420)
                    .help(currentFileName)
            }
            // The title is a label, not a control — drop the toolbar's shared glass
            // capsule so it doesn't read as a dark pill floating in a dark bar.
            .sharedBackgroundVisibility(.hidden)

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    togglePanel(.subtitles)
                } label: {
                    Label(L10n.string("subtitle.panel.toggle"), systemImage: subtitles.status.iconName)
                }
                .help(L10n.string("subtitle.panel.toggle"))

                Menu {
                    panelMenuButton(.playlist, key: "playlist.panel.toggle", systemImage: "list.bullet")
                        .disabled(playlistStore.items.isEmpty)
                    panelMenuButton(.media, key: "media.panel.toggle", systemImage: "info.circle")
                } label: {
                    Label(L10n.string("player.inspector"), systemImage: "sidebar.right")
                }
                .help(L10n.string("player.inspector"))

                Button(action: openVideo) {
                    Label(L10n.string("player.open_video"), systemImage: "folder")
                }
                .help(L10n.string("player.open_video"))

                Button { isNetworkBrowserPresented = true } label: {
                    Label(L10n.string("network.browser.open"), systemImage: "externaldrive.badge.wifi")
                }
                .help(L10n.string("network.browser.open"))
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { isNetworkBrowserPresented = true } label: {
                    Label(L10n.string("network.browser.open"), systemImage: "externaldrive.badge.wifi")
                }
                .help(L10n.string("network.browser.open"))

                Button(action: openVideo) {
                    Label(L10n.string("player.open_video"), systemImage: "folder")
                }
                .buttonStyle(.glassProminent)
                .help(L10n.string("player.open_video"))
            }
        }
    }

    private var videoStage: some View {
        ZStack {
            // Video needs a true black ground; the empty stage needs colour behind
            // it or every glass surface on top would render as flat grey.
            if playback.currentVideoURL == nil {
                GlazeAmbientBackdrop()
            } else {
                Color.black
            }

            if playback.activePlaybackEngine == .nativeVLC, let currentVideoURL = playback.currentVideoURL {
                NativeVLCSurfaceView(url: currentVideoURL, session: playback.nativeVLCSession) { message in
                    playback.errorMessage = "\(L10n.string("player.error.native_engine_unavailable")) \(message)"
                }
                subtitleOverlay
            } else if let player = playback.player {
                PlayerSurfaceView(player: player)
                subtitleOverlay
            } else {
                emptyStage
            }

            if playback.currentVideoURL != nil {
                playerChrome
            }

            if let errorMessage = playback.errorMessage {
                playbackNotice(errorMessage)
            }

            if isDropTargeted {
                dropTargetOverlay
            }
        }
        .clipped()
        // Focusable for the space-bar shortcut, but without AppKit's focus ring:
        // on a view this size the ring draws an accent-coloured line across the top
        // of the picture for the whole of playback.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            playback.togglePlayback()
            revealControls()
            return .handled
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                revealControls()
            case .ended:
                // Pointer left the video — no reason to keep waiting the full idle delay.
                scheduleControlsToHide(after: PlayerView.controlsExitDelay)
            }
        }
        .onChange(of: controlActiveState) { _, state in
            // Clicking outside the player should leave nothing but the picture.
            if state == .inactive {
                hideControlsTask?.cancel()
                areControlsVisible = false
            } else {
                revealControls()
            }
        }
        .onChange(of: playback.displayedIsPlaying) { _, _ in
            revealControls()
        }
        .onTapGesture(count: 2) {
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
    }

    private var emptyStage: some View {
        VStack(spacing: 22) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 46, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 92, height: 92)
                .glazeGlass(.card, cornerRadius: 26, tint: GlazeGlass.amber)

            VStack(spacing: 8) {
                Text(L10n.string("player.empty_title"))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(L10n.string("player.empty_subtitle"))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button(action: openVideo) {
                    Label(L10n.string("player.open_video"), systemImage: "folder")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button { isNetworkBrowserPresented = true } label: {
                    Label(L10n.string("network.browser.open"), systemImage: "externaldrive.badge.wifi")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Label(L10n.string("player.drop_subtitle"), systemImage: "arrow.down.doc")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 52)
        .padding(.vertical, 44)
        .frame(maxWidth: 560)
        .glazeGlass(.pane, cornerRadius: GlazeGlass.Radius.stage)
    }

    private var playerChrome: some View {
        ZStack {
            // Scrims keep the corner controls and the scrubber legible over bright
            // footage without dimming the middle of the frame.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 108)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 168)
            }
            .allowsHitTesting(false)

            transportControls
        }
        .opacity(areControlsVisible ? 1 : 0)
        .allowsHitTesting(areControlsVisible)
        .animation(.easeOut(duration: 0.18), value: areControlsVisible)
    }

    private var transportControls: some View {
        PlayerTransportControls(
            title: currentFileName,
            contextLine: playbackContextLine,
            isPlaying: playback.displayedIsPlaying,
            currentTime: playback.displayedCurrentTime,
            duration: playback.displayedDuration,
            volume: playback.displayedVolume,
            canPlayPrevious: canPlayPrevious,
            canPlayNext: canPlayNext,
            subtitleStatusIcon: subtitles.status.iconName,
            subtitleStatusTitle: L10n.string(subtitles.status.titleKey),
            hasSubtitles: !subtitles.subtitleCues.isEmpty,
            areSubtitlesVisible: subtitles.isSubtitleVisible,
            onPlayPause: {
                playback.togglePlayback()
                revealControls()
            },
            onSkip: playback.skip,
            onSeek: playback.seek,
            onVolumeChange: playback.setVolume,
            onPrevious: playPreviousPlaylistItem,
            onNext: playNextPlaylistItem,
            onOpenSubtitles: { togglePanel(.subtitles) },
            onToggleSubtitles: { subtitles.isSubtitleVisible.toggle() },
            onGenerateSubtitles: { activePanel = .subtitles },
            onToggleFullScreen: { NSApp.keyWindow?.toggleFullScreen(nil) },
            onSeekingChanged: { editing in
                isSeeking = editing
                editing ? hideControlsTask?.cancel() : scheduleControlsToHide()
            }
        )
    }

    private func revealControls() {
        hideControlsTask?.cancel()
        areControlsVisible = true
        scheduleControlsToHide()
    }

    /// Controls only auto-hide during playback: while paused they are what the
    /// viewer is looking for, so they stay until the window goes inactive.
    private func scheduleControlsToHide(after delay: Duration = PlayerView.controlsIdleDelay) {
        hideControlsTask?.cancel()
        guard playback.displayedIsPlaying, !isSeeking else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hideControls()
        }
    }

    private func hideControls() {
        areControlsVisible = false
        // Take the pointer with them; it returns on the next mouse move, which is
        // the same gesture that brings the controls back.
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private var subtitleOverlay: some View {
        VStack {
            Spacer()
            if subtitles.isSubtitleVisible, !subtitles.activeSubtitleText.isEmpty {
                Text(subtitles.activeSubtitleText)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .glazeGlass(.floating, cornerRadius: GlazeGlass.Radius.card)
                    .padding(.horizontal, 32)
                    .padding(.bottom, areControlsVisible ? 124 : 34)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: subtitles.activeSubtitleText)
        .animation(.easeOut(duration: 0.18), value: areControlsVisible)
    }

    private var dropTargetOverlay: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.34))

            RoundedRectangle(cornerRadius: GlazeGlass.Radius.stage, style: .continuous)
                .strokeBorder(
                    GlazeGlass.amber.opacity(0.85),
                    style: StrokeStyle(lineWidth: 2, dash: [9, 7])
                )
                .padding(26)

            VStack(spacing: 11) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(GlazeGlass.amber)
                Text(L10n.string("player.drop_hint"))
                    .font(.title3.weight(.semibold))
                Text(L10n.string("player.drop_subtitle"))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            .glazeGlass(.floating, cornerRadius: GlazeGlass.Radius.panel, tint: GlazeGlass.amber)
        }
    }

    private func playbackNotice(_ message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                if playback.isPreparingCompatibilityPlayback {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Text(message).font(.callout).lineLimit(2)
                Spacer()
                Button {
                    activePanel = .media
                } label: {
                    Label(L10n.string("media.panel.toggle"), systemImage: "info.circle")
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .glazeGlass(.floating, cornerRadius: GlazeGlass.Radius.card, tint: .orange)
            .padding(18)
            Spacer()
        }
        .foregroundStyle(.white)
    }

    private var playerInspector: some View {
        VStack(spacing: 0) {
            Picker(L10n.string("player.inspector"), selection: panelSelection) {
                Label(L10n.string("subtitle.panel.toggle"), systemImage: "captions.bubble").tag(PlayerPanel.subtitles)
                Label(L10n.string("playlist.panel.toggle"), systemImage: "list.bullet").tag(PlayerPanel.playlist)
                Label(L10n.string("media.panel.toggle"), systemImage: "info.circle").tag(PlayerPanel.media)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            .glazeGlass(.floating, cornerRadius: 0, stroked: false)

            panelView(for: activePanel ?? .subtitles)
                .scrollContentBackground(.hidden)
        }
        // The inspector is a separate column from the video, so it gets its own
        // (unanimated — it sits still next to moving footage) backdrop to refract.
        .background {
            GlazeAmbientBackdrop(isAnimated: false)
        }
    }

    private var panelSelection: Binding<PlayerPanel> {
        Binding(
            get: { activePanel ?? .subtitles },
            set: { activePanel = $0 }
        )
    }

    private var subtitlePanel: some View {
        Form {
            Section {
                LabeledContent {
                    Text(subtitles.panelSpokenLanguageValue)
                } label: {
                    GlazeHelpLabel("subtitle.panel.language", help: "help.subtitle.language")
                }
                LabeledContent {
                    Text(subtitles.panelOutputValue)
                } label: {
                    GlazeHelpLabel("subtitle.panel.output", help: "help.subtitle.current")
                }
                Picker(selection: $subtitles.transcriptionTier) {
                    ForEach(TranscriptionModelTier.allCases, id: \.self) { tier in
                        Text(L10n.string(tier.labelKey)).tag(tier)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.model.tier", help: "help.subtitle.model_tier")
                }
                .disabled(subtitles.isGenerating)

                Text(
                    String(
                        format: L10n.string("subtitle.model.download_format"),
                        subtitles.transcriptionTier.approximateDownloadMegabytes
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                // Both timings live here rather than beside their own controls: the
                // translation section disappears once a translation succeeds, and a
                // measurement that vanishes the moment you take it is no use for
                // comparing model tiers.
                if let duration = subtitles.lastGenerationDuration {
                    measuredDuration("subtitle.measured.generation_format", duration)
                }

                if let duration = subtitles.lastTranslationDuration {
                    measuredDuration("subtitle.measured.translation_format", duration)
                }
                Picker(selection: $subtitles.storageLocation) {
                    ForEach(SubtitleStorageLocation.allCases, id: \.self) { location in
                        Text(L10n.string(location.labelKey)).tag(location)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.panel.storage", help: "help.subtitle.storage")
                }
            } header: {
                inspectorHeader("subtitle.panel.title", detailKey: "subtitle.panel.subtitle")
            }
            .glazeGlassRow()

            Section {
                subtitleFileSection
                Toggle(L10n.string("subtitle.visibility.toggle"), isOn: $subtitles.isSubtitleVisible)
                    .disabled(subtitles.subtitleCues.isEmpty)
            } header: {
                GlazeHelpLabel("subtitle.panel.files", help: "help.subtitle.files")
                    .textCase(nil)
            }
            .glazeGlassRow()

            if subtitles.pendingTranslationRequest != nil || subtitles.isTranslating {
                Section(L10n.string("subtitle.translate.section")) {
                    translationSection
                }
                .glazeGlassRow()
            }

            if let errorMessage = subtitles.errorMessage {
                Section { issueLabel(titleKey: "subtitle.error.title", message: errorMessage) }
                    .glazeGlassRow()
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            subtitleActions
        }
    }

    private var subtitleActions: some View {
        VStack(spacing: 8) {
            Divider()
            if subtitles.isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(generationStageText).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.string("subtitle.generate.cancel")) { subtitles.cancelGenerating() }
                }
            } else {
                HStack {
                    Button(action: importSubtitle) {
                        Label(L10n.string("subtitle.import"), systemImage: "text.badge.plus")
                    }
                    Spacer()
                    Button(action: generateSubtitle) {
                        Label(L10n.string("subtitle.generate"), systemImage: "sparkles")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(12)
        .glazeGlass(.floating, cornerRadius: 0, stroked: false)
    }

    /// Offered when a subtitle is loaded in a language the viewer did not ask for —
    /// `SubtitlePreparationPlanner` marks that case and leaves the request pending.
    @ViewBuilder
    private var translationSection: some View {
        if subtitles.isTranslating {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: subtitles.translationProgress)
                Text(
                    String(
                        format: L10n.string("subtitle.translate.progress_format"),
                        Int((subtitles.translationProgress * 100).rounded())
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(role: .cancel) {
                subtitles.cancelTranslating()
            } label: {
                Label(L10n.string("subtitle.translate.cancel"), systemImage: "xmark.circle")
            }
        } else {
            if let request = subtitles.pendingTranslationRequest {
                Text(
                    String(
                        format: L10n.string("subtitle.translate.available_format"),
                        request.source.displayName,
                        languageDisplayName(request.targetLanguageCode)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Only the system engine ships today; on-device AI and an external
            // endpoint are the planned tiers, so the row states which one is running
            // rather than offering a choice that does not exist yet.
            Picker(selection: $subtitles.translationEngineID) {
                Text(L10n.string(SubtitleTranslationEngineID.appleTranslation.labelKey))
                    .tag(SubtitleTranslationEngineID.appleTranslation)
                Text(L10n.string(SubtitleTranslationEngineID.appleFoundationModel.labelKey))
                    .tag(SubtitleTranslationEngineID.appleFoundationModel)
            } label: {
                GlazeHelpLabel("subtitle.translate.engine", help: "help.subtitle.translate_engine")
            }

            if subtitles.translationEngineID == .appleFoundationModel {
                if let reason = subtitles.onDeviceModelUnavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.string("subtitle.translate.engine.on_device_ai_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Strategy is a lever on the system translator only; the on-device model
            // is steered by its instructions instead.
            if subtitles.translationEngineID == .appleTranslation {
                Picker(selection: $subtitles.translationQuality) {
                    ForEach(SubtitleTranslationQuality.allCases, id: \.self) { quality in
                        Text(L10n.string(quality.labelKey)).tag(quality)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.translate.quality", help: "help.subtitle.translate_quality")
                }
            }

            Picker(selection: $subtitles.translationOutput) {
                ForEach(SubtitleTranslationOutput.allCases, id: \.self) { output in
                    Text(L10n.string(output.labelKey)).tag(output)
                }
            } label: {
                GlazeHelpLabel("subtitle.translate.output", help: "help.subtitle.translate_output")
            }

            Button {
                guard let videoURL = playback.currentVideoURL else { return }
                subtitles.startTranslating(for: videoURL)
            } label: {
                Label(L10n.string("subtitle.translate.action"), systemImage: "character.bubble")
            }
            .disabled(
                !subtitles.canTranslate
                    || playback.currentVideoURL == nil
                    || (subtitles.translationEngineID == .appleFoundationModel
                        && subtitles.onDeviceModelUnavailableReason != nil)
            )
        }
    }

    private func measuredDuration(_ formatKey: String, _ duration: TimeInterval) -> some View {
        Text(String(format: L10n.string(formatKey), formattedDuration(duration)))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Comparing model tiers only means anything against a measured number.
    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return seconds >= 60
            ? String(format: "%d:%02d", seconds / 60, seconds % 60)
            : "\(seconds)s"
    }

    private func languageDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private var subtitleFileSection: some View {
        Group {
            if subtitles.isInspectingEmbeddedSubtitles,
               subtitles.detectedSubtitles.isEmpty,
               subtitles.embeddedSubtitleTracks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.string("subtitle.embedded.inspecting"))
                }
                .foregroundStyle(.secondary)
            } else if subtitles.detectedSubtitles.isEmpty,
                      subtitles.embeddedSubtitleTracks.isEmpty {
                Label(L10n.string("subtitle.panel.files_empty"), systemImage: "captions.bubble")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subtitles.detectedSubtitles) { subtitle in
                    Button { subtitles.load(subtitle) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subtitle.displayName).lineLimit(1)
                                Text(subtitles.kindLabel(for: subtitle.kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if subtitles.selectedSubtitlePath == subtitle.url.path {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(subtitles.embeddedSubtitleTracks) { track in
                    Button {
                        guard let videoURL = playback.currentVideoURL else { return }
                        subtitles.loadEmbedded(track, from: videoURL)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subtitles.embeddedTrackLabel(track)).lineLimit(1)
                                Text(track.codec.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if subtitles.selectedEmbeddedTrackID == track.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            } else if !track.canProvideTimedText {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.secondary)
                                    .help(L10n.string("subtitle.embedded.bitmap_hint"))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!track.canProvideTimedText)
                }
            }
        }
    }

    private var playlistPanel: some View {
        List(playlistStore.items, selection: Binding<String?>(
            get: { playback.currentVideoURL?.absoluteString },
            set: { identifier in
                guard let item = playlistStore.items.first(where: { $0.url.absoluteString == identifier }) else { return }
                loadVideo(item.url, playlist: playlistStore.items, shouldStartPlayback: true)
            }
        )) { item in
            Label(item.displayName, systemImage: playback.currentVideoURL?.absoluteString == item.url.absoluteString ? "play.fill" : "film")
                .tag(item.url.absoluteString)
                .glazeGlassRow()
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top) {
            inspectorTitleBar("playlist.panel.title", detail: playlistSummary)
        }
        .overlay {
            if playlistStore.items.isEmpty {
                ContentUnavailableView(L10n.string("playlist.panel.empty"), systemImage: "list.bullet")
            }
        }
    }

    private var mediaPanel: some View {
        Form {
            Section {
                if mediaAssets.isInspectingMedia {
                    HStack { ProgressView().controlSize(.small); Text(L10n.string("media.panel.inspecting")) }
                } else if let inspection = mediaAssets.mediaInspection {
                    LabeledContent {
                        Text(inspection.containerHint.isEmpty ? "–" : inspection.containerHint)
                    } label: {
                        GlazeHelpLabel("media.panel.container", help: "help.media.container")
                    }
                    LabeledContent(L10n.string("media.panel.duration"), value: inspection.duration)
                    LabeledContent {
                        Text(avKitSupportText(for: inspection.isPlayable))
                    } label: {
                        GlazeHelpLabel("media.panel.avkit", help: "help.media.playback")
                    }

                    if let asset = mediaAssets.currentMediaAsset {
                        LabeledContent {
                            Text(L10n.string(asset.source.labelKey))
                        } label: {
                            GlazeHelpLabel("assistant.media.source", help: "help.assistant.source")
                        }
                    }
                } else {
                    Label(L10n.string("media.panel.empty"), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } header: {
                inspectorHeader("media.panel.title", detailKey: "media.panel.subtitle")
            }
            .glazeGlassRow()

            if let inspection = mediaAssets.mediaInspection, !inspection.tracks.isEmpty {
                Section {
                    ForEach(inspection.tracks) { track in
                        LabeledContent {
                            Text(track.detail).foregroundStyle(.secondary).lineLimit(2)
                        } label: {
                            Label("\(track.title) · \(track.codec)", systemImage: mediaTrackIcon(for: track.title))
                        }
                    }
                } header: {
                    GlazeHelpLabel("media.panel.tracks", help: "help.media.tracks")
                        .textCase(nil)
                }
                .glazeGlassRow()
            }

            if let message = mediaAssets.mediaInspection?.errorMessage {
                Section { issueLabel(titleKey: "media.error.title", message: message) }
                    .glazeGlassRow()
            }
        }
        .formStyle(.grouped)
    }

    private func inspectorHeader(_ titleKey: String, detailKey: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string(titleKey)).font(.title2.weight(.semibold)).textCase(nil)
            Text(L10n.string(detailKey)).font(.caption).foregroundStyle(.secondary).textCase(nil)
        }
        .padding(.bottom, 8)
    }

    private func inspectorTitleBar(_ titleKey: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(titleKey)).font(.title2.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .glazeGlass(.floating, cornerRadius: 0, stroked: false)
    }

    private func issueLabel(titleKey: String, message: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(titleKey)).fontWeight(.semibold)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var generationStageText: String {
        switch subtitles.generationStage {
        case .extractingAudio: L10n.string("subtitle.generating.stage.extracting_audio")
        case .preparingModel: L10n.string("subtitle.generating.stage.preparing_model")
        case .transcribing: L10n.string("subtitle.generating.stage.transcribing")
        case .none: L10n.string("subtitle.status.generating")
        }
    }

    private func configureControllers() {
        playback.onTimeUpdate = { time in subtitles.updateActiveCue(at: time) }
        playback.onPlaybackFailureNeedsAttention = { activePanel = .media }
        playback.onPlaybackEnded = { playNextPlaylistItem() }
        playback.onCompatibilityRemuxSucceeded = { originalURL, remuxedURL in
            loadVideo(originalURL: originalURL, playbackURL: remuxedURL, playlist: playlistStore.items, shouldStartPlayback: true)
        }
        subtitles.onGenerationFinished = { mediaAssets.markSubtitleGenerated() }
        subtitles.onEmbeddedSubtitleLoaded = { mediaAssets.markSubtitleEmbeddedLoaded() }
    }

    private func handlePlaybackEnd(_ notification: Notification) {
        guard let endedItem = notification.object as? AVPlayerItem,
              endedItem === playback.player?.currentItem else { return }
        playNextPlaylistItem()
    }

    private func generateSubtitle() {
        guard let url = playback.currentVideoURL else { return }
        subtitles.startGenerating(from: url)
    }

    private func openVideo() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("open_panel.title")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedVideoTypes + [.folder]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openMedia(from: url)
    }

    private func openMedia(from url: URL) {
        let nextPlaylist = MediaPlaylistBuilder.initialPlaylist(for: url)
        guard let firstItem = nextPlaylist.first else {
            playback.errorMessage = L10n.string("player.error.no_playable_files")
            return
        }
        loadVideo(firstItem.url, playlist: nextPlaylist, shouldStartPlayback: true)
        activePanel = MediaPlaylistBuilder.isDirectory(url) && nextPlaylist.count > 1 ? .playlist : nil
        expandPlaylistInBackground(for: url, currentItem: firstItem.url)
        revealControls()
    }

    private func openNetworkMedia(_ resource: NetworkMediaResource, server: NetworkMediaServer) {
        let item = MediaPlaylistItem(url: resource.playbackURL)
        loadVideo(
            item.url,
            playlist: [item],
            shouldStartPlayback: true,
            resource: .network(resource),
            source: .dlna(serverID: server.id, serverName: server.friendlyName)
        )
        activePanel = nil
        revealControls()
    }

    private func loadVideo(
        _ url: URL,
        playlist nextPlaylist: [MediaPlaylistItem],
        shouldStartPlayback: Bool,
        resource: MediaResource? = nil,
        source: MediaLibrarySource = .localFolder
    ) {
        switch PlaybackEngineRouter.preferredEngine(for: url) {
        case .nativeVLC:
            playback.loadWithNativeEngine(url)
            prepareCurrentMediaState(
                originalURL: url,
                playlist: nextPlaylist,
                resource: resource,
                source: source
            )
        case .avkit, .none:
            loadVideo(
                originalURL: url,
                playbackURL: url,
                playlist: nextPlaylist,
                shouldStartPlayback: shouldStartPlayback,
                resource: resource,
                source: source
            )
        }
    }

    private func loadVideo(
        originalURL: URL,
        playbackURL: URL,
        playlist nextPlaylist: [MediaPlaylistItem],
        shouldStartPlayback: Bool,
        resource: MediaResource? = nil,
        source: MediaLibrarySource = .localFolder
    ) {
        playback.loadWithAVKit(originalURL: originalURL, playbackURL: playbackURL, shouldStartPlayback: shouldStartPlayback)
        prepareCurrentMediaState(
            originalURL: originalURL,
            playlist: nextPlaylist,
            resource: resource,
            source: source
        )
    }

    private func prepareCurrentMediaState(
        originalURL: URL,
        playlist nextPlaylist: [MediaPlaylistItem],
        resource: MediaResource? = nil,
        source: MediaLibrarySource = .localFolder
    ) {
        playlistStore.setInitial(nextPlaylist)
        let mediaResource = resource ?? .localFile(originalURL)
        playback.setCurrentResource(mediaResource)
        subtitles.currentResource = mediaResource
        subtitles.prepareForNewVideo(url: originalURL)
        mediaAssets.prepareForNewVideo(
            url: originalURL,
            hasDetectedSubtitles: !subtitles.detectedSubtitles.isEmpty,
            engine: playback.activePlaybackEngine,
            resource: resource,
            source: source,
            isStillCurrent: { playback.currentVideoURL == originalURL }
        )
    }

    private func expandPlaylistInBackground(for sourceURL: URL, currentItem: URL) {
        playlistStore.expandInBackground(
            for: sourceURL,
            currentItem: currentItem,
            isStillCurrent: { playback.currentVideoURL?.standardizedFileURL == currentItem.standardizedFileURL }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in openMedia(from: url) }
        }
        return true
    }

    private func importSubtitle() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("subtitle.import_panel.title")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedSubtitleTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        subtitles.importManual(url: url)
        mediaAssets.markSubtitleExternallyLoaded()
        playback.errorMessage = nil
        activePanel = .subtitles
    }

    private func avKitSupportText(for isPlayable: Bool?) -> String {
        switch isPlayable {
        case .some(true): L10n.string("media.panel.avkit_playable")
        case .some(false): L10n.string("media.panel.avkit_not_playable")
        case .none: L10n.string("media.panel.avkit_unknown")
        }
    }

    private func mediaTrackIcon(for title: String) -> String {
        switch title {
        case "Video": "film"
        case "Audio": "waveform"
        case "Subtitle", "Text", "Closed Caption": "captions.bubble"
        default: "questionmark.circle"
        }
    }

    private enum PlayerPanel: Hashable {
        case subtitles, playlist, media
    }

    private func togglePanel(_ panel: PlayerPanel) {
        activePanel = activePanel == panel ? nil : panel
    }

    @ViewBuilder
    private func panelView(for panel: PlayerPanel) -> some View {
        switch panel {
        case .subtitles: subtitlePanel
        case .playlist: playlistPanel
        case .media: mediaPanel
        }
    }

    private func panelMenuButton(_ panel: PlayerPanel, key: String, systemImage: String) -> some View {
        Button { togglePanel(panel) } label: { Label(L10n.string(key), systemImage: systemImage) }
    }

    /// Runs one translation pass through whichever engine was chosen. The system
    /// translator arrives via `.translationTask` because its session can only be
    /// vended by SwiftUI; the on-device model is constructed directly.
    private func runTranslation(
        input: SubtitleController.TranslationInput,
        engine: some SubtitleTranslationEngine
    ) async {
        do {
            let translations = try await engine.translate(
                segments: input.segments,
                targetLanguageCode: input.targetLanguageCode,
                onProgress: { progress in
                    subtitles.updateTranslationProgress(progress)
                }
            )
            subtitles.applyTranslation(translations, for: input)
        } catch {
            subtitles.failTranslating(error)
        }
    }

    /// Caption above the title in the bottom bar — playlist position when there is
    /// one to report, otherwise where the video came from.
    private var playbackContextLine: String? {
        if playlistStore.items.count > 1, let index = currentPlaylistIndex {
            return String(
                format: L10n.string("playlist.panel.position_format"),
                index + 1,
                playlistStore.items.count
            )
        }
        if let source = mediaAssets.currentMediaAsset?.source {
            return L10n.string(source.labelKey)
        }
        return nil
    }

    private var playlistSummary: String {
        String(format: L10n.string("playlist.panel.count_format"), playlistStore.items.count)
    }

    private var currentPlaylistIndex: Int? {
        guard let currentVideoURL = playback.currentVideoURL else { return nil }
        return playlistStore.items.firstIndex { $0.url.path == currentVideoURL.path }
    }

    private var canPlayPrevious: Bool { (currentPlaylistIndex ?? 0) > 0 }

    private var canPlayNext: Bool {
        guard let currentPlaylistIndex else { return false }
        return currentPlaylistIndex < playlistStore.items.count - 1
    }

    private func playPreviousPlaylistItem() {
        guard let index = currentPlaylistIndex, index > 0 else { return }
        loadVideo(playlistStore.items[index - 1].url, playlist: playlistStore.items, shouldStartPlayback: true)
    }

    private func playNextPlaylistItem() {
        guard let index = currentPlaylistIndex, index < playlistStore.items.count - 1 else { return }
        loadVideo(playlistStore.items[index + 1].url, playlist: playlistStore.items, shouldStartPlayback: true)
    }

    private var supportedVideoTypes: [UTType] {
        var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .audiovisualContent]
        types += ["mkv", "webm", "avi"].compactMap { UTType(filenameExtension: $0) }
        return types
    }

    private var supportedSubtitleTypes: [UTType] {
        ["srt", "vtt", "smi"].compactMap { UTType(filenameExtension: $0) }
    }
}

#Preview {
    PlayerView().frame(width: 1100, height: 700)
}
