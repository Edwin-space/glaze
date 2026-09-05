import GlazeCore
import SwiftUI

/// Full-screen playback with controls that get out of the way.
struct IOSPlayerView: View {
    let resource: NetworkMediaResource
    let title: String
    var startAt: TimeInterval = 0
    var subtitleURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var model = IOSPlaybackModel()
    @State private var showsControls = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            IOSVideoSurface(player: model.player).ignoresSafeArea()

            if showsControls {
                controls.transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { revealControls() }
        .animation(.easeOut(duration: 0.2), value: showsControls)
        .onAppear {
            model.start(resource, at: startAt, subtitleURL: subtitleURL)
            revealControls()
        }
        .onDisappear {
            hideTask?.cancel()
            model.stop()
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .padding(10)
                        .background(.black.opacity(0.45), in: Circle())
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .padding(.leading, 4)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()

            transport

            timeline
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
    }

    private var transport: some View {
        HStack(spacing: 44) {
            Button { model.skip(by: -10); revealControls() } label: {
                Image(systemName: "gobackward.10").font(.title)
            }
            Button { model.togglePlayback(); revealControls() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
            }
            Button { model.skip(by: 10); revealControls() } label: {
                Image(systemName: "goforward.10").font(.title)
            }
        }
        .padding(.bottom, 20)
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            ProgressView(value: model.duration > 0 ? model.currentTime / model.duration : 0)
                .tint(IOSTheme.amber)
            HStack {
                Text(Self.timecode(model.currentTime))
                Spacer()
                Text(Self.timecode(model.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    /// Controls appear on a tap and leave again on their own; a film with a bar across
    /// it is not what anyone came to watch.
    private func revealControls() {
        showsControls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            showsControls = false
        }
    }

    private static func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
