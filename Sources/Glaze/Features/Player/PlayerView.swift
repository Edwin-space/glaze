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
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                showsSubtitlePanel.toggle()
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
            GlazeColors.playerBackground

            if let player {
                VideoPlayer(player: player)
                subtitleOverlay
            } else {
                emptyState
            }
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

    private func openVideo() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("open_panel.title")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedVideoTypes

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        removeTimeObserver()

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        currentFileName = url.lastPathComponent
        errorMessage = nil
        detectedSubtitles = SubtitleSidecarDetector.detect(for: url)
        subtitleCues = []
        activeSubtitleText = ""
        isSubtitleVisible = true
        selectedSubtitleName = nil
        selectedSubtitlePath = nil
        loadPreferredSubtitleIfAvailable()
        installTimeObserver(on: nextPlayer)
        nextPlayer.play()
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
