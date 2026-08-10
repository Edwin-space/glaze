import GlazeCore
import SwiftUI

struct PlayerTransportControls: View {
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let volume: Double
    let canPlayPrevious: Bool
    let canPlayNext: Bool
    let subtitleStatusIcon: String
    let subtitleStatusTitle: String
    let hasSubtitles: Bool
    let areSubtitlesVisible: Bool

    let onPlayPause: () -> Void
    let onSkip: (TimeInterval) -> Void
    let onSeek: (TimeInterval) -> Void
    let onVolumeChange: (Double) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onOpenSubtitles: () -> Void
    let onToggleSubtitles: () -> Void
    let onGenerateSubtitles: () -> Void
    let onToggleFullScreen: () -> Void
    let onSeekingChanged: (Bool) -> Void

    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0

    var body: some View {
        VStack(spacing: 12) {
            timeline
            transportButtons
            accessoryButtons
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .foregroundStyle(.white)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(formattedTime(displayedTime))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { seekPosition = $0 }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: handleSeeking
            )

            Text("−\(formattedTime(duration - displayedTime))")
                .monospacedDigit()
                .frame(width: 58, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.72))
    }

    private var transportButtons: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Button(action: onPrevious) {
                    Label(L10n.string("player.previous_video"), systemImage: "backward.end.fill")
                }
                .disabled(!canPlayPrevious)

                Button { onSkip(-15) } label: {
                    Label(L10n.string("player.rewind"), systemImage: "gobackward.15")
                }
            }

            Spacer()

            Button(action: onPlayPause) {
                Label(
                    L10n.string(isPlaying ? "player.pause" : "player.play"),
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
                .font(.title2.weight(.semibold))
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)

            Spacer()

            HStack(spacing: 4) {
                Button { onSkip(15) } label: {
                    Label(L10n.string("player.forward"), systemImage: "goforward.15")
                }

                Button(action: onNext) {
                    Label(L10n.string("player.next_video"), systemImage: "forward.end.fill")
                }
                .disabled(!canPlayNext)
            }
        }
        .labelStyle(.iconOnly)
    }

    private var accessoryButtons: some View {
        HStack(spacing: 12) {
            Button(action: onOpenSubtitles) {
                Label(L10n.string("subtitle.panel.toggle"), systemImage: subtitleStatusIcon)
            }
            .help(subtitleStatusTitle)

            if hasSubtitles {
                Button(action: onToggleSubtitles) {
                    Label(
                        L10n.string(areSubtitlesVisible ? "subtitle.visibility.hide" : "subtitle.visibility.show"),
                        systemImage: areSubtitlesVisible ? "captions.bubble.fill" : "captions.bubble"
                    )
                }
            } else {
                Button(action: onGenerateSubtitles) {
                    Label(L10n.string("subtitle.generate"), systemImage: "sparkles")
                }
                .tint(.accentColor)
            }

            Spacer()

            Image(systemName: volumeSymbol)
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityHidden(true)

            Slider(
                value: Binding(get: { volume }, set: { onVolumeChange($0) }),
                in: 0...1
            )
            .frame(width: 92)
            .accessibilityLabel(L10n.string("player.volume"))

            Button(action: onToggleFullScreen) {
                Label(L10n.string("player.full_screen"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .labelStyle(.iconOnly)
        }
        .font(.callout)
    }

    private var displayedTime: TimeInterval {
        isSeeking ? seekPosition : currentTime
    }

    private var volumeSymbol: String {
        switch volume {
        case ...0.001: "speaker.slash.fill"
        case ..<0.5: "speaker.wave.1.fill"
        default: "speaker.wave.2.fill"
        }
    }

    private func handleSeeking(_ editing: Bool) {
        isSeeking = editing
        if editing {
            seekPosition = currentTime
        } else {
            onSeek(seekPosition)
        }
        onSeekingChanged(editing)
    }

    private func formattedTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let seconds = Int(value.rounded(.down))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
