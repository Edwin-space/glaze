import GlazeCore
import SwiftUI

/// Watching one film, from the sofa.
///
/// The controls are deliberately sparse. On a remote with no pointer, every extra
/// affordance is another thing to arrow past, so this is play/pause, skip, and a
/// progress line — the same vocabulary every other Apple TV app uses.
struct TVPlayerView: View {
    let resource: NetworkMediaResource
    let title: String
    /// Where to start. Non-zero when the viewer chose to resume.
    var startAt: TimeInterval = 0

    @Environment(\.dismiss) private var dismiss
    @State private var model = TVPlaybackModel()
    @State private var areControlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVVideoSurface(player: model.player).ignoresSafeArea()

            if model.hasFailed {
                failure
            } else if areControlsVisible {
                controls.transition(.opacity)
            }
        }
        // Without this the view receives nothing from the remote. tvOS delivers
        // play/pause and arrow presses to the focused view, and a ZStack of video and
        // an overlay that hides itself has nothing focusable in it — the first version
        // looked like it worked only because the film kept playing under the
        // screenshots.
        .focusable()
        .onAppear {
            model.start(resource, at: startAt)
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            // Remember where they got to before tearing the player down.
            model.rememberPosition(for: resource)
            model.stop()
        }
        .onExitCommand { dismiss() }
        // The remote's play/pause button, and a click on the touch surface.
        .onPlayPauseCommand { toggle() }
        .onMoveCommand { direction in
            reveal()
            switch direction {
            case .left: model.skip(-TVPlaybackModel.skipInterval)
            case .right: model.skip(TVPlaybackModel.skipInterval)
            default: break
            }
        }
        .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
    }

    private var controls: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.white)

                HStack {
                    Text(timecode(model.currentTime))
                    Spacer()
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    Spacer()
                    Text(timecode(model.duration))
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(40)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(60)
        }
    }

    private var failure: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(L10n.string("tv.playback.failed.title")).font(.title2)
            Text(L10n.string("tv.playback.failed.detail"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)
            Button(L10n.string("network.browser.back")) { dismiss() }
                .padding(.top, 12)
        }
    }

    private var progress: Double {
        guard model.duration > 0 else { return 0 }
        return min(1, model.currentTime / model.duration)
    }

    private func toggle() {
        model.togglePlayPause()
        reveal()
    }

    private func reveal() {
        areControlsVisible = true
        scheduleHide()
    }

    /// Controls get out of the way on their own; there is no cursor to move away.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            areControlsVisible = false
        }
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
