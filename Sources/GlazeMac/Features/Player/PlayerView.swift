import AVKit
import GlazeCore
import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    @State private var playback = PlaybackController()
    @State private var playlistStore = PlaylistStore()
    @State private var subtitles = SubtitleController()
    @State private var mediaAssets = MediaAssetStore()

    @State private var activePanel: PlayerPanel?
    @State private var isDropTargeted = false
    @State private var areControlsVisible = true
    @State private var isSeeking = false
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        videoStage
            .inspector(isPresented: inspectorPresentation) {
                playerInspector
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
            .toolbar { playerToolbar }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime), perform: handlePlaybackEnd)
            .onReceive(NotificationCenter.default.publisher(for: .openVideoCommand)) { _ in openVideo() }
            .onReceive(NotificationCenter.default.publisher(for: .openMediaURL)) { notification in
                guard let url = notification.object as? URL else { return }
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
                    .lineLimit(1)
                    .frame(maxWidth: 420)
                    .help(currentFileName)
            }

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
                    panelMenuButton(.assistant, key: "assistant.panel.toggle", systemImage: "sparkles")
                } label: {
                    Label(L10n.string("player.inspector"), systemImage: "sidebar.right")
                }
                .help(L10n.string("player.inspector"))

                Button(action: openVideo) {
                    Label(L10n.string("player.open_video"), systemImage: "folder")
                }
                .help(L10n.string("player.open_video"))
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
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
            Color.black

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
        .background(.black)
        .clipped()
        .focusable()
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
                scheduleControlsToHide()
            }
        }
        .onTapGesture(count: 2) {
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
    }

    private var emptyStage: some View {
        ZStack {
            RadialGradient(
                colors: [Color.white.opacity(0.075), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )

            VStack(spacing: 20) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 48, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.72))

                VStack(spacing: 7) {
                    Text(L10n.string("player.empty_title"))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(L10n.string("player.empty_subtitle"))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.56))
                        .multilineTextAlignment(.center)
                }

                Button(action: openVideo) {
                    Label(L10n.string("player.open_video"), systemImage: "folder")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Label(L10n.string("player.drop_subtitle"), systemImage: "arrow.down.doc")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
            }
            .frame(maxWidth: 520)
            .padding(48)
        }
    }

    private var playerChrome: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.52), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .opacity(areControlsVisible ? 1 : 0)

            Spacer()

            transportControls
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
                .opacity(areControlsVisible ? 1 : 0)
                .offset(y: areControlsVisible ? 0 : 12)
                .allowsHitTesting(areControlsVisible)
        }
        .animation(.easeOut(duration: 0.18), value: areControlsVisible)
    }

    private var transportControls: some View {
        PlayerTransportControls(
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
        areControlsVisible = true
        scheduleControlsToHide()
    }

    private func scheduleControlsToHide() {
        hideControlsTask?.cancel()
        guard playback.displayedIsPlaying, !isSeeking else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            areControlsVisible = false
        }
    }

    private var subtitleOverlay: some View {
        VStack {
            Spacer()
            if subtitles.isSubtitleVisible, !subtitles.activeSubtitleText.isEmpty {
                Text(subtitles.activeSubtitleText)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 3)
                    .padding(.horizontal, 32)
                    .padding(.bottom, areControlsVisible ? 166 : 34)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: subtitles.activeSubtitleText)
        .animation(.easeOut(duration: 0.18), value: areControlsVisible)
    }

    private var dropTargetOverlay: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.62))
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.68), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(28)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 36, weight: .medium))
                Text(L10n.string("player.drop_hint"))
                    .font(.title3.weight(.semibold))
                Text(L10n.string("player.drop_subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Label(L10n.string("assistant.panel.toggle"), systemImage: "sparkles").tag(PlayerPanel.assistant)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()
            panelView(for: activePanel ?? .subtitles)
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
                LabeledContent(L10n.string("subtitle.panel.language"), value: L10n.string("subtitle.panel.auto_detect"))
                LabeledContent(L10n.string("subtitle.panel.output"), value: subtitles.panelOutputValue)
                LabeledContent(L10n.string("subtitle.panel.mode"), value: L10n.string("subtitle.panel.mode_standard"))
                LabeledContent(L10n.string("subtitle.panel.storage"), value: L10n.string("subtitle.panel.storage_ask"))
            } header: {
                inspectorHeader("subtitle.panel.title", detailKey: "subtitle.panel.subtitle")
            }

            Section(L10n.string("subtitle.panel.files")) {
                subtitleFileSection
                Toggle(L10n.string("subtitle.visibility.toggle"), isOn: $subtitles.isSubtitleVisible)
                    .disabled(subtitles.subtitleCues.isEmpty)
            }

            if let errorMessage = subtitles.errorMessage {
                Section { issueLabel(titleKey: "subtitle.error.title", message: errorMessage) }
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
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var subtitleFileSection: some View {
        Group {
            if subtitles.detectedSubtitles.isEmpty {
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
            }
        }
    }

    private var playlistPanel: some View {
        List(playlistStore.items, selection: Binding<String?>(
            get: { playback.currentVideoURL?.path },
            set: { path in
                guard let item = playlistStore.items.first(where: { $0.url.path == path }) else { return }
                loadVideo(item.url, playlist: playlistStore.items, shouldStartPlayback: true)
            }
        )) { item in
            Label(item.displayName, systemImage: playback.currentVideoURL?.path == item.url.path ? "play.fill" : "film")
                .tag(item.url.path)
        }
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
                    LabeledContent(L10n.string("media.panel.container"), value: inspection.containerHint.isEmpty ? "–" : inspection.containerHint)
                    LabeledContent(L10n.string("media.panel.duration"), value: inspection.duration)
                    LabeledContent(L10n.string("media.panel.avkit"), value: avKitSupportText(for: inspection.isPlayable))
                } else {
                    Label(L10n.string("media.panel.empty"), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } header: {
                inspectorHeader("media.panel.title", detailKey: "media.panel.subtitle")
            }

            if let inspection = mediaAssets.mediaInspection, !inspection.tracks.isEmpty {
                Section(L10n.string("media.panel.tracks")) {
                    ForEach(inspection.tracks) { track in
                        LabeledContent {
                            Text(track.detail).foregroundStyle(.secondary).lineLimit(2)
                        } label: {
                            Label("\(track.title) · \(track.codec)", systemImage: mediaTrackIcon(for: track.title))
                        }
                    }
                }
            }

            if let message = mediaAssets.mediaInspection?.errorMessage {
                Section { issueLabel(titleKey: "media.error.title", message: message) }
            }
        }
        .formStyle(.grouped)
    }

    private var assistantPanel: some View {
        Form {
            Section {
                if let asset = mediaAssets.currentMediaAsset {
                    LabeledContent(L10n.string("assistant.metadata.status"), value: L10n.string(asset.metadata.matchStatus.labelKey))
                    LabeledContent(L10n.string("assistant.subtitle.status"), value: L10n.string(asset.subtitleReadiness.labelKey))
                    LabeledContent(L10n.string("assistant.media.source"), value: L10n.string(asset.source.labelKey))
                } else {
                    Label(L10n.string("assistant.panel.empty"), systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                }
            } header: {
                inspectorHeader("assistant.panel.title", detailKey: "assistant.panel.subtitle")
            }

            if mediaAssets.currentMediaAsset != nil {
                Section(L10n.string("assistant.panel.suggestions")) {
                    assistantAction("assistant.action.match_metadata", detailKey: "assistant.action.match_metadata_hint", icon: "magnifyingglass")
                    assistantAction("assistant.action.prepare_subtitles", detailKey: "assistant.action.prepare_subtitles_hint", icon: "captions.bubble")
                    assistantAction("assistant.action.write_metadata", detailKey: "assistant.action.write_metadata_hint", icon: "square.and.pencil")
                }
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
        .background(.bar)
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

    private func assistantAction(_ titleKey: String, detailKey: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(titleKey))
                Text(L10n.string(detailKey)).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
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
        playback.onCompatibilityRemuxSucceeded = { originalURL, remuxedURL in
            loadVideo(originalURL: originalURL, playbackURL: remuxedURL, playlist: playlistStore.items, shouldStartPlayback: true)
        }
        subtitles.onGenerationFinished = { mediaAssets.markSubtitleGenerated() }
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

    private func loadVideo(_ url: URL, playlist nextPlaylist: [MediaPlaylistItem], shouldStartPlayback: Bool) {
        switch PlaybackEngineRouter.preferredEngine(for: url) {
        case .nativeVLC:
            playback.loadWithNativeEngine(url)
            prepareCurrentMediaState(originalURL: url, playlist: nextPlaylist)
        case .avkit, .none:
            loadVideo(originalURL: url, playbackURL: url, playlist: nextPlaylist, shouldStartPlayback: shouldStartPlayback)
        }
    }

    private func loadVideo(originalURL: URL, playbackURL: URL, playlist nextPlaylist: [MediaPlaylistItem], shouldStartPlayback: Bool) {
        playback.loadWithAVKit(originalURL: originalURL, playbackURL: playbackURL, shouldStartPlayback: shouldStartPlayback)
        prepareCurrentMediaState(originalURL: originalURL, playlist: nextPlaylist)
    }

    private func prepareCurrentMediaState(originalURL: URL, playlist nextPlaylist: [MediaPlaylistItem]) {
        playlistStore.setInitial(nextPlaylist)
        subtitles.prepareForNewVideo(url: originalURL)
        mediaAssets.prepareForNewVideo(
            url: originalURL,
            hasDetectedSubtitles: !subtitles.detectedSubtitles.isEmpty,
            engine: playback.activePlaybackEngine,
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
        case subtitles, playlist, media, assistant
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
        case .assistant: assistantPanel
        }
    }

    private func panelMenuButton(_ panel: PlayerPanel, key: String, systemImage: String) -> some View {
        Button { togglePanel(panel) } label: { Label(L10n.string(key), systemImage: systemImage) }
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
