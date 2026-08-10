import AVKit
import GlazeCore
import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    @State private var playback = PlaybackController()
    @State private var playlistStore = PlaylistStore()
    @State private var subtitles = SubtitleController()
    @State private var mediaAssets = MediaAssetStore()

    @State private var showsSubtitlePanel = false
    @State private var showsMediaPanel = false
    @State private var showsPlaylistPanel = false
    @State private var showsAssistantPanel = false
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                videoSurface
                subtitleStatusStrip
            }

            if showsSubtitlePanel {
                subtitlePanel
            }

            if showsMediaPanel {
                mediaPanel
            }

            if showsPlaylistPanel {
                playlistPanel
            }

            if showsAssistantPanel {
                assistantPanel
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let endedItem = notification.object as? AVPlayerItem,
                  endedItem === playback.player?.currentItem else {
                return
            }

            playNextPlaylistItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVideoCommand)) { _ in
            openVideo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMediaURL)) { notification in
            guard let url = notification.object as? URL else {
                return
            }

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
            playback.stopForWindowClose()
        }
    }

    /// Wires the four controllers together. Called from `.onAppear`; safe to call more than once.
    private func configureControllers() {
        playback.onTimeUpdate = { time in
            subtitles.updateActiveCue(at: time)
        }
        playback.onPlaybackFailureNeedsAttention = {
            showsMediaPanel = true
            showsPlaylistPanel = false
            showsSubtitlePanel = false
            showsAssistantPanel = false
        }
        playback.onCompatibilityRemuxSucceeded = { originalURL, remuxedURL in
            loadVideo(
                originalURL: originalURL,
                playbackURL: remuxedURL,
                playlist: playlistStore.items,
                shouldStartPlayback: true
            )
        }
        subtitles.onGenerationFinished = {
            mediaAssets.markSubtitleGenerated()
        }
    }

    private var currentFileName: String {
        playback.currentVideoURL?.lastPathComponent ?? L10n.string("player.no_file")
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("app.name"))
                    .font(.system(.headline, design: .rounded))
                Text(currentFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let errorMessage = playback.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(playback.isPreparingCompatibilityPlayback ? Color.secondary : Color.red)
                    .lineLimit(1)
            }

            Button {
                togglePanel(.media)
            } label: {
                Label(L10n.string("media.panel.toggle"), systemImage: "info.circle")
            }
            .buttonStyle(.glass)
            .disabled(playback.currentVideoURL == nil)

            Button {
                togglePanel(.subtitles)
            } label: {
                Label(L10n.string("subtitle.panel.toggle"), systemImage: "captions.bubble")
            }
            .buttonStyle(.glass)

            Button {
                openVideo()
            } label: {
                Label(L10n.string("player.open_video"), systemImage: "folder")
            }
            .buttonStyle(.glassProminent)
        }
        .padding(16)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, GlazeSpacing.md)
        .padding(.top, GlazeSpacing.md)
    }

    private var videoSurface: some View {
        ZStack {
            LinearGradient(
                colors: [GlazeColors.kiln, GlazeColors.kiln2, GlazeColors.kiln],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                RadialGradient(
                    colors: [GlazeColors.glaze.opacity(0.22), .clear],
                    center: UnitPoint(x: 0.18, y: 0.1),
                    startRadius: 0,
                    endRadius: 620
                )
            }
            .overlay {
                RadialGradient(
                    colors: [GlazeColors.celadon.opacity(0.12), .clear],
                    center: UnitPoint(x: 0.86, y: 0.94),
                    startRadius: 0,
                    endRadius: 520
                )
            }

            if playback.activePlaybackEngine == .nativeVLC, let currentVideoURL = playback.currentVideoURL {
                NativeVLCSurfaceView(url: currentVideoURL) { message in
                    playback.errorMessage = "\(L10n.string("player.error.native_engine_unavailable")) \(message)"
                }
                subtitleOverlay
            } else if let player = playback.player {
                PlayerSurfaceView(player: player)
                subtitleOverlay
            } else {
                emptyState
            }

            playerChrome

            if isDropTargeted {
                dropTargetOverlay
            }

            assistantBubble
        }
    }

    private var playerChrome: some View {
        VStack {
            GlassEffectContainer(spacing: GlazeSpacing.sm) {
            HStack(spacing: GlazeSpacing.sm) {
                Spacer()

                iconButton(
                    key: "player.previous_video",
                    systemImage: "backward.end",
                    isActive: false,
                    isDisabled: !canPlayPrevious
                ) {
                    playPreviousPlaylistItem()
                }

                iconButton(
                    key: "player.next_video",
                    systemImage: "forward.end",
                    isActive: false,
                    isDisabled: !canPlayNext
                ) {
                    playNextPlaylistItem()
                }

                iconButton(
                    key: "assistant.panel.toggle",
                    systemImage: "sparkles",
                    isActive: showsAssistantPanel,
                    isDisabled: playback.currentVideoURL == nil
                ) {
                    togglePanel(.assistant)
                }

                iconButton(
                    key: "media.panel.toggle",
                    systemImage: "info.circle",
                    isActive: showsMediaPanel,
                    isDisabled: playback.currentVideoURL == nil
                ) {
                    togglePanel(.media)
                }

                iconButton(
                    key: "playlist.panel.toggle",
                    systemImage: "list.bullet",
                    isActive: showsPlaylistPanel,
                    isDisabled: playlistStore.items.isEmpty
                ) {
                    togglePanel(.playlist)
                }

                iconButton(
                    key: "subtitle.panel.toggle",
                    systemImage: "captions.bubble",
                    isActive: showsSubtitlePanel,
                    isDisabled: false
                ) {
                    togglePanel(.subtitles)
                }

                iconButton(
                    key: subtitles.isSubtitleVisible ? "subtitle.visibility.hide" : "subtitle.visibility.show",
                    systemImage: subtitles.isSubtitleVisible ? "captions.bubble.fill" : "captions.bubble",
                    isActive: subtitles.isSubtitleVisible && !subtitles.subtitleCues.isEmpty,
                    isDisabled: subtitles.subtitleCues.isEmpty
                ) {
                    subtitles.isSubtitleVisible.toggle()
                }

                iconButton(
                    key: "player.open_video",
                    systemImage: "folder",
                    isActive: false,
                    isDisabled: false
                ) {
                    openVideo()
                }
            }
            .padding(GlazeSpacing.md)
            }

            Spacer()
        }
    }

    private var dropTargetOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(GlazeColors.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .glassEffect(.regular.tint(GlazeColors.accent), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: GlazeSpacing.sm) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 34, weight: .medium))
                Text(L10n.string("player.drop_hint"))
                    .font(.system(.headline, design: .rounded))
                Text(L10n.string("player.drop_subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
        .padding(GlazeSpacing.xl)
    }

    private var assistantBubble: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button {
                    togglePanel(.assistant)
                } label: {
                    HStack(spacing: GlazeSpacing.sm) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.string("assistant.bubble.title"))
                                .font(.caption.weight(.semibold))
                            Text(assistantBubbleSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, GlazeSpacing.md)
                    .padding(.vertical, GlazeSpacing.sm)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
                .disabled(playback.currentVideoURL == nil)
                .opacity(playback.currentVideoURL == nil ? 0.42 : 1)
            }
            .padding(GlazeSpacing.lg)
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
                    .padding(.horizontal, GlazeSpacing.lg)
                    .padding(.vertical, GlazeSpacing.sm)
                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
                    .padding(.horizontal, GlazeSpacing.xl)
                    .padding(.bottom, 56)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: subtitles.activeSubtitleText)
    }

    private var emptyState: some View {
        VStack(spacing: 30) {
            VesselSignatureView()

            VStack(spacing: 9) {
                Text(L10n.string("player.empty_title"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(GlazeColors.porcelain)

                Text(L10n.string("player.empty_subtitle"))
                    .font(.system(size: 15))
                    .foregroundStyle(GlazeColors.ash)
            }
            .frame(maxWidth: 440)
            .multilineTextAlignment(.center)

            Button {
                openVideo()
            } label: {
                Label(L10n.string("player.open_video"), systemImage: "folder")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text(L10n.string("player.drop_subtitle"))
                .font(.caption)
                .foregroundStyle(GlazeColors.ash.opacity(0.7))
        }
        .padding(40)
    }

    private var subtitleStatusStrip: some View {
        HStack(spacing: GlazeSpacing.md) {
            Label(L10n.string(subtitles.status.titleKey), systemImage: subtitles.status.iconName)
                .font(.caption.weight(.medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(subtitles.status.tint)

            Text(subtitles.statusHint(hasPlayer: playback.player != nil))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                subtitles.isSubtitleVisible.toggle()
            } label: {
                Label(
                    L10n.string(subtitles.isSubtitleVisible ? "subtitle.visibility.hide" : "subtitle.visibility.show"),
                    systemImage: subtitles.isSubtitleVisible ? "captions.bubble.fill" : "captions.bubble"
                )
            }
            .buttonStyle(.glass)
            .disabled(subtitles.subtitleCues.isEmpty)

            Button {
                showsSubtitlePanel = true
            } label: {
                Label(L10n.string("subtitle.generate"), systemImage: "sparkles")
            }
            .buttonStyle(.glass)
            .disabled(playback.currentVideoURL == nil)
        }
        .padding(.horizontal, GlazeSpacing.lg)
        .padding(.vertical, GlazeSpacing.sm)
        .background(.regularMaterial)
    }

    private var subtitlePanel: some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: GlazeSpacing.xs) {
                    Text(L10n.string("subtitle.panel.title"))
                        .font(.system(.headline, design: .rounded))
                    Text(L10n.string("subtitle.panel.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showsSubtitlePanel = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: GlazeSpacing.md) {
                panelRow(icon: "waveform", titleKey: "subtitle.panel.language", valueKey: "subtitle.panel.auto_detect")
                panelRow(icon: "captions.bubble", titleKey: "subtitle.panel.output", value: subtitles.panelOutputValue)
                panelRow(icon: "speedometer", titleKey: "subtitle.panel.mode", valueKey: "subtitle.panel.mode_standard")
                panelRow(icon: "folder", titleKey: "subtitle.panel.storage", valueKey: "subtitle.panel.storage_ask")
            }

            subtitleFileSection

            Toggle(
                L10n.string("subtitle.visibility.toggle"),
                isOn: Binding(
                    get: { subtitles.isSubtitleVisible },
                    set: { subtitles.isSubtitleVisible = $0 }
                )
            )
            .disabled(subtitles.subtitleCues.isEmpty)

            if let errorMessage = subtitles.errorMessage {
                subtitleErrorCard(errorMessage)
            }

            Spacer()

            if subtitles.isGenerating {
                generationProgressCard
            } else {
                Button {
                    importSubtitle()
                } label: {
                    Label(L10n.string("subtitle.import"), systemImage: "text.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(playback.currentVideoURL == nil)

                Button {
                    generateSubtitle()
                } label: {
                    Label(L10n.string("subtitle.generate"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(playback.currentVideoURL == nil)
            }
        }
        .padding(GlazeSpacing.lg)
        .frame(width: 300)
        .background(GlazeColors.panelBackground)
    }

    private var generationProgressCard: some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.sm) {
            HStack(spacing: GlazeSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text(generationStageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                subtitles.cancelGenerating()
            } label: {
                Label(L10n.string("subtitle.generate.cancel"), systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }

    private var generationStageText: String {
        switch subtitles.generationStage {
        case .extractingAudio:
            L10n.string("subtitle.generating.stage.extracting_audio")
        case .preparingModel:
            L10n.string("subtitle.generating.stage.preparing_model")
        case .transcribing:
            L10n.string("subtitle.generating.stage.transcribing")
        case .none:
            L10n.string("subtitle.status.generating")
        }
    }

    private func generateSubtitle() {
        guard let url = playback.currentVideoURL else {
            return
        }

        subtitles.startGenerating(from: url)
    }

    private var playlistPanel: some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: GlazeSpacing.xs) {
                    Text(L10n.string("playlist.panel.title"))
                        .font(.system(.headline, design: .rounded))
                    Text(playlistSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showsPlaylistPanel = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            if playlistStore.items.isEmpty {
                Text(L10n.string("playlist.panel.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GlazeSpacing.md)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: GlazeSpacing.xs) {
                        ForEach(playlistStore.items) { item in
                            Button {
                                loadVideo(item.url, playlist: playlistStore.items, shouldStartPlayback: true)
                            } label: {
                                HStack(spacing: GlazeSpacing.sm) {
                                    Image(systemName: playback.currentVideoURL?.path == item.url.path ? "play.circle.fill" : "film")
                                        .foregroundStyle(playback.currentVideoURL?.path == item.url.path ? GlazeColors.accent : .secondary)

                                    Text(item.displayName)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(GlazeSpacing.sm)
                            .background(
                                playback.currentVideoURL?.path == item.url.path ? GlazeColors.subtlePanel : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(GlazeSpacing.lg)
        .frame(width: 300)
        .background(GlazeColors.panelBackground)
    }

    private var assistantPanel: some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: GlazeSpacing.xs) {
                    Text(L10n.string("assistant.panel.title"))
                        .font(.system(.headline, design: .rounded))
                    Text(L10n.string("assistant.panel.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showsAssistantPanel = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            if let currentMediaAsset = mediaAssets.currentMediaAsset {
                VStack(alignment: .leading, spacing: GlazeSpacing.md) {
                    Text(currentMediaAsset.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    panelRow(icon: "sparkles.tv", titleKey: "assistant.metadata.status", value: L10n.string(currentMediaAsset.metadata.matchStatus.labelKey))
                    panelRow(icon: "captions.bubble", titleKey: "assistant.subtitle.status", value: L10n.string(currentMediaAsset.subtitleReadiness.labelKey))
                    panelRow(icon: "externaldrive", titleKey: "assistant.media.source", value: L10n.string(currentMediaAsset.source.labelKey))
                }

                VStack(alignment: .leading, spacing: GlazeSpacing.sm) {
                    assistantActionRow(icon: "magnifyingglass", titleKey: "assistant.action.match_metadata", subtitleKey: "assistant.action.match_metadata_hint")
                    assistantActionRow(icon: "text.badge.checkmark", titleKey: "assistant.action.prepare_subtitles", subtitleKey: "assistant.action.prepare_subtitles_hint")
                    assistantActionRow(icon: "square.and.pencil", titleKey: "assistant.action.write_metadata", subtitleKey: "assistant.action.write_metadata_hint")
                }
            } else {
                Text(L10n.string("assistant.panel.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GlazeSpacing.md)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(GlazeSpacing.lg)
        .frame(width: 340)
        .background(GlazeColors.panelBackground)
    }

    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: GlazeSpacing.xs) {
                    Text(L10n.string("media.panel.title"))
                        .font(.system(.headline, design: .rounded))
                    Text(L10n.string("media.panel.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showsMediaPanel = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            if mediaAssets.isInspectingMedia {
                HStack(spacing: GlazeSpacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("media.panel.inspecting"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let mediaInspection = mediaAssets.mediaInspection {
                mediaSummary(mediaInspection)
                mediaTrackSection(mediaInspection)

                if let errorMessage = mediaInspection.errorMessage {
                    mediaIssueCard(errorMessage)
                }
            } else {
                Text(L10n.string("media.panel.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GlazeSpacing.md)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(GlazeSpacing.lg)
        .frame(width: 320)
        .background(GlazeColors.panelBackground)
    }

    private func mediaSummary(_ inspection: MediaInspection) -> some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.md) {
            panelRow(icon: "shippingbox", titleKey: "media.panel.container", value: inspection.containerHint.isEmpty ? "-" : inspection.containerHint)
            panelRow(icon: "clock", titleKey: "media.panel.duration", value: inspection.duration)
            panelRow(icon: "play.rectangle", titleKey: "media.panel.avkit", value: avKitSupportText(for: inspection.isPlayable))
        }
    }

    private func mediaTrackSection(_ inspection: MediaInspection) -> some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.sm) {
            Text(L10n.string("media.panel.tracks"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if inspection.tracks.isEmpty {
                Text(L10n.string("media.panel.tracks_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GlazeSpacing.md)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: GlazeSpacing.xs) {
                        ForEach(inspection.tracks) { track in
                            HStack(alignment: .top, spacing: GlazeSpacing.sm) {
                                Image(systemName: mediaTrackIcon(for: track.title))
                                    .frame(width: 22)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(track.title) · \(track.codec)")
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(track.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()
                            }
                            .padding(GlazeSpacing.sm)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private func mediaIssueCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: GlazeSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("media.error.title"))
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(GlazeSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var subtitleFileSection: some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.sm) {
            HStack {
                Text(L10n.string("subtitle.panel.files"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !subtitles.detectedSubtitles.isEmpty {
                    Text(String(format: L10n.string("subtitle.panel.files_count_format"), subtitles.detectedSubtitles.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if subtitles.detectedSubtitles.isEmpty {
                Text(L10n.string("subtitle.panel.files_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GlazeSpacing.md)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: GlazeSpacing.xs) {
                        ForEach(subtitles.detectedSubtitles) { subtitle in
                            Button {
                                subtitles.load(subtitle)
                            } label: {
                                HStack(spacing: GlazeSpacing.sm) {
                                    Image(systemName: subtitles.selectedSubtitlePath == subtitle.url.path ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(subtitles.selectedSubtitlePath == subtitle.url.path ? .green : .secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(subtitle.displayName)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                        Text(subtitles.kindLabel(for: subtitle.kind))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(GlazeSpacing.sm)
                            .background(
                                subtitles.selectedSubtitlePath == subtitle.url.path ? GlazeColors.subtlePanel : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private func subtitleErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: GlazeSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("subtitle.error.title"))
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(GlazeSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func panelRow(icon: String, titleKey: String, valueKey: String) -> some View {
        panelRow(icon: icon, titleKey: titleKey, value: L10n.string(valueKey))
    }

    private func panelRow(icon: String, titleKey: String, value: String) -> some View {
        HStack(spacing: GlazeSpacing.sm) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(titleKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
            }

            Spacer()
        }
        .padding(GlazeSpacing.md)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
    }

    private func assistantActionRow(icon: String, titleKey: String, subtitleKey: String) -> some View {
        HStack(alignment: .top, spacing: GlazeSpacing.sm) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(GlazeColors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(titleKey))
                    .font(.callout.weight(.medium))
                Text(L10n.string(subtitleKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(GlazeSpacing.md)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
    }

    private func iconButton(
        key: String,
        systemImage: String,
        isActive: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(isActive ? .white : .white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isActive ? .regular.tint(GlazeColors.accent).interactive() : .regular.interactive(),
            in: Circle()
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(L10n.string(key))
    }

    private func openVideo() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("open_panel.title")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedVideoTypes + [.folder]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openMedia(from: url)
    }

    private func openMedia(from url: URL) {
        let nextPlaylist = MediaPlaylistBuilder.initialPlaylist(for: url)
        guard let firstItem = nextPlaylist.first else {
            playback.errorMessage = L10n.string("player.error.no_playable_files")
            return
        }

        loadVideo(firstItem.url, playlist: nextPlaylist, shouldStartPlayback: true)
        showsPlaylistPanel = MediaPlaylistBuilder.isDirectory(url) && nextPlaylist.count > 1
        expandPlaylistInBackground(for: url, currentItem: firstItem.url)
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

    /// Resets playlist, subtitle, and media-asset state for a newly loaded video across all three stores.
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
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            Task { @MainActor in
                openMedia(from: url)
            }
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

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        subtitles.importManual(url: url)
        mediaAssets.markSubtitleExternallyLoaded()
        playback.errorMessage = nil
        showsSubtitlePanel = true
    }

    private func avKitSupportText(for isPlayable: Bool?) -> String {
        switch isPlayable {
        case .some(true):
            L10n.string("media.panel.avkit_playable")
        case .some(false):
            L10n.string("media.panel.avkit_not_playable")
        case .none:
            L10n.string("media.panel.avkit_unknown")
        }
    }

    private func mediaTrackIcon(for title: String) -> String {
        switch title {
        case "Video":
            "film"
        case "Audio":
            "waveform"
        case "Subtitle", "Text", "Closed Caption":
            "captions.bubble"
        default:
            "questionmark.circle"
        }
    }

    private enum PlayerPanel {
        case media
        case playlist
        case subtitles
        case assistant
    }

    private func togglePanel(_ panel: PlayerPanel) {
        switch panel {
        case .media:
            showsMediaPanel.toggle()
            showsPlaylistPanel = false
            showsSubtitlePanel = false
            showsAssistantPanel = false
        case .playlist:
            showsPlaylistPanel.toggle()
            showsMediaPanel = false
            showsSubtitlePanel = false
            showsAssistantPanel = false
        case .subtitles:
            showsSubtitlePanel.toggle()
            showsMediaPanel = false
            showsPlaylistPanel = false
            showsAssistantPanel = false
        case .assistant:
            showsAssistantPanel.toggle()
            showsMediaPanel = false
            showsPlaylistPanel = false
            showsSubtitlePanel = false
        }
    }

    private var playlistSummary: String {
        String(format: L10n.string("playlist.panel.count_format"), playlistStore.items.count)
    }

    private var assistantBubbleSubtitle: String {
        guard let currentMediaAsset = mediaAssets.currentMediaAsset else {
            return L10n.string("assistant.bubble.empty")
        }

        return L10n.string(currentMediaAsset.subtitleReadiness.labelKey)
    }

    private var currentPlaylistIndex: Int? {
        guard let currentVideoURL = playback.currentVideoURL else {
            return nil
        }

        return playlistStore.items.firstIndex { $0.url.path == currentVideoURL.path }
    }

    private var canPlayPrevious: Bool {
        guard let currentPlaylistIndex else {
            return false
        }

        return currentPlaylistIndex > 0
    }

    private var canPlayNext: Bool {
        guard let currentPlaylistIndex else {
            return false
        }

        return currentPlaylistIndex < playlistStore.items.count - 1
    }

    private func playPreviousPlaylistItem() {
        guard let currentPlaylistIndex, currentPlaylistIndex > 0 else {
            return
        }

        loadVideo(playlistStore.items[currentPlaylistIndex - 1].url, playlist: playlistStore.items, shouldStartPlayback: true)
    }

    private func playNextPlaylistItem() {
        guard let currentPlaylistIndex, currentPlaylistIndex < playlistStore.items.count - 1 else {
            return
        }

        loadVideo(playlistStore.items[currentPlaylistIndex + 1].url, playlist: playlistStore.items, shouldStartPlayback: true)
    }

    private var supportedVideoTypes: [UTType] {
        var types: [UTType] = [
            .movie,
            .video,
            .mpeg4Movie,
            .quickTimeMovie,
            .audiovisualContent
        ]

        for extensionName in ["mkv", "webm", "avi"] {
            if let type = UTType(filenameExtension: extensionName) {
                types.append(type)
            }
        }

        return types
    }

    private var supportedSubtitleTypes: [UTType] {
        ["srt", "vtt", "smi"].compactMap { UTType(filenameExtension: $0) }
    }
}

#Preview {
    PlayerView()
        .frame(width: 960, height: 620)
}
