import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    @State private var player: AVPlayer?
    @State private var currentFileName = L10n.string("player.no_file")
    @State private var errorMessage: String?
    @State private var subtitleStatus: SubtitleStatus = .noVideo
    @State private var detectedSubtitles: [SubtitleFile] = []
    @State private var subtitleCues: [SubtitleCue] = []
    @State private var activeSubtitleText = ""
    @State private var isSubtitleVisible = true
    @State private var timeObserver: Any?
    @State private var observedPlayer: AVPlayer?
    @State private var selectedSubtitleName: String?
    @State private var selectedSubtitlePath: String?
    @State private var showsSubtitlePanel = false
    @State private var showsMediaPanel = false
    @State private var mediaInspection: MediaInspection?
    @State private var isInspectingMedia = false
    @State private var currentVideoURL: URL?
    @State private var playlist: [MediaPlaylistItem] = []
    @State private var showsPlaylistPanel = false
    @State private var showsAssistantPanel = false
    @State private var currentMediaAsset: MediaAsset?
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
                  endedItem === player?.currentItem else {
                return
            }

            playNextPlaylistItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVideoCommand)) { _ in
            openVideo()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("app.name"))
                    .font(.headline)
                Text(currentFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Button {
                togglePanel(.media)
            } label: {
                Label(L10n.string("media.panel.toggle"), systemImage: "info.circle")
            }
            .buttonStyle(.bordered)
            .disabled(player == nil)

            Button {
                togglePanel(.subtitles)
            } label: {
                Label(L10n.string("subtitle.panel.toggle"), systemImage: "captions.bubble")
            }
            .buttonStyle(.bordered)

            Button {
                openVideo()
            } label: {
                Label(L10n.string("player.open_video"), systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private var videoSurface: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(nsColor: .windowBackgroundColor).opacity(0.92), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let player {
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
                    isDisabled: player == nil
                ) {
                    togglePanel(.assistant)
                }

                iconButton(
                    key: "media.panel.toggle",
                    systemImage: "info.circle",
                    isActive: showsMediaPanel,
                    isDisabled: player == nil
                ) {
                    togglePanel(.media)
                }

                iconButton(
                    key: "playlist.panel.toggle",
                    systemImage: "list.bullet",
                    isActive: showsPlaylistPanel,
                    isDisabled: playlist.isEmpty
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
                    key: isSubtitleVisible ? "subtitle.visibility.hide" : "subtitle.visibility.show",
                    systemImage: isSubtitleVisible ? "captions.bubble.fill" : "captions.bubble",
                    isActive: isSubtitleVisible && !subtitleCues.isEmpty,
                    isDisabled: subtitleCues.isEmpty
                ) {
                    isSubtitleVisible.toggle()
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
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.52), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()
        }
    }

    private var dropTargetOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(GlazeColors.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: GlazeSpacing.sm) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 34, weight: .medium))
                Text(L10n.string("player.drop_hint"))
                    .font(.headline)
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
                    .background(.black.opacity(0.58), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(player == nil)
                .opacity(player == nil ? 0.42 : 1)
            }
            .padding(GlazeSpacing.lg)
        }
    }

    private var subtitleOverlay: some View {
        VStack {
            Spacer()

            if isSubtitleVisible, !activeSubtitleText.isEmpty {
                Text(activeSubtitleText)
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
        .animation(.easeInOut(duration: 0.12), value: activeSubtitleText)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(L10n.string("player.empty_title"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text(L10n.string("player.empty_subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button {
                openVideo()
            } label: {
                Label(L10n.string("player.open_video"), systemImage: "folder")
            }
            .keyboardShortcut(.defaultAction)

            Text(L10n.string("player.drop_subtitle"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private var subtitleStatusStrip: some View {
        HStack(spacing: GlazeSpacing.md) {
            StatusBadge(
                title: L10n.string(subtitleStatus.titleKey),
                systemImage: subtitleStatus.iconName,
                tint: subtitleStatus.tint
            )

            Text(subtitleStatusHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                isSubtitleVisible.toggle()
            } label: {
                Label(
                    L10n.string(isSubtitleVisible ? "subtitle.visibility.hide" : "subtitle.visibility.show"),
                    systemImage: isSubtitleVisible ? "captions.bubble.fill" : "captions.bubble"
                )
            }
            .buttonStyle(.bordered)
            .disabled(subtitleCues.isEmpty)

            Button {
                showsSubtitlePanel = true
            } label: {
                Label(L10n.string("subtitle.generate"), systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(player == nil)
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
                        .font(.headline)
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
                panelRow(icon: "captions.bubble", titleKey: "subtitle.panel.output", value: subtitlePanelOutputValue)
                panelRow(icon: "speedometer", titleKey: "subtitle.panel.mode", valueKey: "subtitle.panel.mode_standard")
                panelRow(icon: "folder", titleKey: "subtitle.panel.storage", valueKey: "subtitle.panel.storage_ask")
            }

            subtitleFileSection

            Toggle(L10n.string("subtitle.visibility.toggle"), isOn: $isSubtitleVisible)
                .disabled(subtitleCues.isEmpty)

            if let errorMessage {
                subtitleErrorCard(errorMessage)
            }

            Spacer()

            Button {
                importSubtitle()
            } label: {
                Label(L10n.string("subtitle.import"), systemImage: "text.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(player == nil)

            Button {
                // Placeholder until the AI subtitle pipeline exists.
            } label: {
                Label(L10n.string("subtitle.generate"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(player == nil)
        }
        .padding(GlazeSpacing.lg)
        .frame(width: 300)
        .background(GlazeColors.panelBackground)
    }

    private var playlistPanel: some View {
        VStack(alignment: .leading, spacing: GlazeSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: GlazeSpacing.xs) {
                    Text(L10n.string("playlist.panel.title"))
                        .font(.headline)
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

            if playlist.isEmpty {
                Text(L10n.string("playlist.panel.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GlazeSpacing.md)
                    .background(GlazeColors.subtlePanel, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: GlazeSpacing.xs) {
                        ForEach(playlist) { item in
                            Button {
                                loadVideo(item.url, playlist: playlist, shouldStartPlayback: true)
                            } label: {
                                HStack(spacing: GlazeSpacing.sm) {
                                    Image(systemName: currentVideoURL?.path == item.url.path ? "play.circle.fill" : "film")
                                        .foregroundStyle(currentVideoURL?.path == item.url.path ? GlazeColors.accent : .secondary)

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
                                currentVideoURL?.path == item.url.path ? GlazeColors.subtlePanel : Color.clear,
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
                        .font(.headline)
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

            if let currentMediaAsset {
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
                    .background(GlazeColors.subtlePanel, in: RoundedRectangle(cornerRadius: 8))
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
                        .font(.headline)
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

            if isInspectingMedia {
                HStack(spacing: GlazeSpacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("media.panel.inspecting"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let mediaInspection {
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
                    .background(GlazeColors.subtlePanel, in: RoundedRectangle(cornerRadius: 8))
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
                    .background(GlazeColors.subtlePanel, in: RoundedRectangle(cornerRadius: 8))
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
                            .background(GlazeColors.subtlePanel, in: RoundedRectangle(cornerRadius: 8))
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

                if !detectedSubtitles.isEmpty {
                    Text(String(format: L10n.string("subtitle.panel.files_count_format"), detectedSubtitles.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if detectedSubtitles.isEmpty {
                Text(L10n.string("subtitle.panel.files_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GlazeSpacing.md)
                    .background(GlazeColors.subtlePanel, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: GlazeSpacing.xs) {
                        ForEach(detectedSubtitles) { subtitle in
                            Button {
                                loadSubtitle(subtitle)
                            } label: {
                                HStack(spacing: GlazeSpacing.sm) {
                                    Image(systemName: selectedSubtitlePath == subtitle.url.path ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedSubtitlePath == subtitle.url.path ? .green : .secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(subtitle.displayName)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                        Text(subtitleKindLabel(for: subtitle.kind))
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
                                selectedSubtitlePath == subtitle.url.path ? GlazeColors.subtlePanel : Color.clear,
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
        .background(GlazeColors.subtlePanel, in: RoundedRectangle(cornerRadius: 8))
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
        .background(GlazeColors.subtlePanel, in: RoundedRectangle(cornerRadius: 8))
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
                .foregroundStyle(isActive ? .white : .white.opacity(0.72))
                .background(isActive ? GlazeColors.accent.opacity(0.82) : .black.opacity(0.36), in: Circle())
        }
        .buttonStyle(.plain)
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
        let nextPlaylist = MediaPlaylistBuilder.playlist(for: url)
        guard let firstItem = nextPlaylist.first else {
            errorMessage = L10n.string("player.error.no_playable_files")
            return
        }

        loadVideo(firstItem.url, playlist: nextPlaylist, shouldStartPlayback: true)
        showsPlaylistPanel = nextPlaylist.count > 1
    }

    private func loadVideo(_ url: URL, playlist nextPlaylist: [MediaPlaylistItem], shouldStartPlayback: Bool) {
        removeTimeObserver()

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        playlist = nextPlaylist
        currentVideoURL = url
        currentFileName = url.lastPathComponent
        errorMessage = nil
        mediaInspection = nil
        isInspectingMedia = true
        detectedSubtitles = SubtitleSidecarDetector.detect(for: url)
        currentMediaAsset = mediaAsset(for: url)
        subtitleCues = []
        activeSubtitleText = ""
        isSubtitleVisible = true
        selectedSubtitleName = nil
        selectedSubtitlePath = nil
        loadPreferredSubtitleIfAvailable()
        installTimeObserver(on: nextPlayer)
        inspectMedia(url)
        if shouldStartPlayback {
            nextPlayer.play()
        }
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

        let subtitle = SubtitleFile.manual(url: url)

        if !detectedSubtitles.contains(where: { $0.url.path == subtitle.url.path }) {
            detectedSubtitles.append(subtitle)
        }

        loadSubtitle(subtitle)
        currentMediaAsset?.subtitleReadiness = .externalLoaded
        errorMessage = nil
        showsSubtitlePanel = true
    }

    private var subtitleStatusHint: String {
        guard player != nil else {
            return L10n.string("subtitle.status.hint")
        }

        if let selectedSubtitleName {
            if !isSubtitleVisible, !subtitleCues.isEmpty {
                return String(format: L10n.string("subtitle.status.hidden_hint_format"), selectedSubtitleName)
            }

            return String(format: L10n.string("subtitle.status.loaded_hint_format"), selectedSubtitleName)
        }

        guard !detectedSubtitles.isEmpty else {
            return L10n.string("subtitle.status.generate_or_import_hint")
        }

        let names = detectedSubtitles.map(\.displayName).joined(separator: ", ")
        return String(format: L10n.string("subtitle.status.detected_hint_format"), names)
    }

    private var subtitlePanelOutputValue: String {
        guard !detectedSubtitles.isEmpty else {
            return L10n.string("subtitle.panel.output_dual")
        }

        let hasKorean = detectedSubtitles.contains { $0.kind == .korean }
        return hasKorean ? L10n.string("subtitle.panel.output_korean_available") : L10n.string("subtitle.panel.output_original_available")
    }

    private func status(for subtitles: [SubtitleFile]) -> SubtitleStatus {
        if !subtitleCues.isEmpty {
            return .subtitleLoaded
        }

        guard !subtitles.isEmpty else {
            return .readyToGenerate
        }

        if subtitles.contains(where: { $0.kind == .korean }) {
            return .koreanSubtitleDetected
        }

        return .subtitleDetected
    }

    private func loadPreferredSubtitleIfAvailable() {
        guard let preferredSubtitle = detectedSubtitles.sorted(by: preferredSubtitleSort).first else {
            subtitleStatus = status(for: detectedSubtitles)
            return
        }

        loadSubtitle(preferredSubtitle)
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

    private func loadSubtitle(_ subtitle: SubtitleFile) {
        do {
            subtitleCues = try SubtitleParser.parse(url: subtitle.url)
            selectedSubtitleName = subtitle.displayName
            selectedSubtitlePath = subtitle.url.path
            activeSubtitleText = ""
            isSubtitleVisible = true
            subtitleStatus = status(for: detectedSubtitles)
            errorMessage = nil
        } catch {
            subtitleCues = []
            selectedSubtitleName = nil
            selectedSubtitlePath = nil
            activeSubtitleText = ""
            subtitleStatus = status(for: detectedSubtitles)
            errorMessage = subtitleErrorMessage(for: error)
        }
    }

    private func subtitleKindLabel(for kind: SubtitleFile.Kind) -> String {
        switch kind {
        case .korean:
            L10n.string("subtitle.kind.korean")
        case .original:
            L10n.string("subtitle.kind.original")
        case .unknown:
            L10n.string("subtitle.kind.unknown")
        }
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

    private func inspectMedia(_ url: URL) {
        Task {
            let inspection = await MediaInspector.inspect(url: url)
            await MainActor.run {
                guard currentVideoURL == url else {
                    return
                }

                mediaInspection = inspection
                isInspectingMedia = false
            }
        }
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
        String(format: L10n.string("playlist.panel.count_format"), playlist.count)
    }

    private var assistantBubbleSubtitle: String {
        guard let currentMediaAsset else {
            return L10n.string("assistant.bubble.empty")
        }

        return L10n.string(currentMediaAsset.subtitleReadiness.labelKey)
    }

    private func mediaAsset(for url: URL) -> MediaAsset {
        var asset = MediaAsset(fileURL: url)
        asset.subtitleReadiness = detectedSubtitles.isEmpty ? .missing : .externalLoaded
        return asset
    }

    private var currentPlaylistIndex: Int? {
        guard let currentVideoURL else {
            return nil
        }

        return playlist.firstIndex { $0.url.path == currentVideoURL.path }
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

        return currentPlaylistIndex < playlist.count - 1
    }

    private func playPreviousPlaylistItem() {
        guard let currentPlaylistIndex, currentPlaylistIndex > 0 else {
            return
        }

        loadVideo(playlist[currentPlaylistIndex - 1].url, playlist: playlist, shouldStartPlayback: true)
    }

    private func playNextPlaylistItem() {
        guard let currentPlaylistIndex, currentPlaylistIndex < playlist.count - 1 else {
            return
        }

        loadVideo(playlist[currentPlaylistIndex + 1].url, playlist: playlist, shouldStartPlayback: true)
    }

    private func installTimeObserver(on player: AVPlayer) {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                activeSubtitleText = activeCueText(at: time.seconds)
            }
        }
        observedPlayer = player
    }

    private func removeTimeObserver() {
        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }

        timeObserver = nil
        observedPlayer = nil
    }

    private func activeCueText(at time: TimeInterval) -> String {
        subtitleCues.first { $0.contains(time) }?.text ?? ""
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
