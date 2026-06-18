import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    @State private var player: AVPlayer?
    @State private var currentFileName = L10n.string("player.no_file")
    @State private var errorMessage: String?
    @State private var subtitleStatus: SubtitleStatus = .noVideo
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
            } else {
                emptyState
            }
        }
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

            Text(L10n.string("subtitle.status.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

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
                panelRow(icon: "captions.bubble", titleKey: "subtitle.panel.output", valueKey: "subtitle.panel.output_dual")
                panelRow(icon: "speedometer", titleKey: "subtitle.panel.mode", valueKey: "subtitle.panel.mode_standard")
                panelRow(icon: "folder", titleKey: "subtitle.panel.storage", valueKey: "subtitle.panel.storage_ask")
            }

            Spacer()

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

    private func panelRow(icon: String, titleKey: String, valueKey: String) -> some View {
        HStack(spacing: GlazeSpacing.sm) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(titleKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.string(valueKey))
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

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        currentFileName = url.lastPathComponent
        errorMessage = nil
        subtitleStatus = .readyToGenerate
        nextPlayer.play()
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
}

#Preview {
    PlayerView()
        .frame(width: 960, height: 620)
}
