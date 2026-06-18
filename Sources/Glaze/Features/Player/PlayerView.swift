import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    @State private var player: AVPlayer?
    @State private var currentFileName = L10n.string("player.no_file")
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                Color.black

                if let player {
                    VideoPlayer(player: player)
                } else {
                    emptyState
                }
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
                openVideo()
            } label: {
                Label(L10n.string("player.open_video"), systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
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
