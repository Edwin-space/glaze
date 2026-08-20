import GlazeCore
import SwiftUI

/// Playback chrome laid out over the whole video stage rather than packed into a
/// single bottom bar: transport sits in the centre where the eye already is, the
/// scrubber spans the full width at the very bottom, and secondary controls sit
/// in the corners. Mirrors how Apple's own TV app arranges a playing video.
struct PlayerTransportControls: View {
    let title: String
    let contextLine: String?
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
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
            }

            centerTransport

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Top

    private var topBar: some View {
        HStack {
            Spacer()
            volumeControl
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    private var volumeControl: some View {
        HStack(spacing: 9) {
            Image(systemName: volumeSymbol)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 16)
                .accessibilityHidden(true)

            Slider(
                value: Binding(get: { volume }, set: { onVolumeChange($0) }),
                in: 0...1
            )
            .controlSize(.mini)
            .frame(width: 92)
            .accessibilityLabel(L10n.string("player.volume"))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .glazeGlass(.floating, cornerRadius: 999)
    }

    // MARK: - Centre

    private var centerTransport: some View {
        HStack(spacing: 26) {
            if canPlayPrevious || canPlayNext {
                circleButton(
                    L10n.string("player.previous_video"),
                    systemImage: "backward.end.fill",
                    diameter: 44,
                    glyph: 15
                ) { onPrevious() }
                .disabled(!canPlayPrevious)
            }

            circleButton(
                L10n.string("player.rewind"),
                systemImage: "gobackward.10",
                diameter: 58,
                glyph: 22
            ) { onSkip(-10) }

            circleButton(
                L10n.string(isPlaying ? "player.pause" : "player.play"),
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                diameter: 86,
                glyph: 33,
                action: onPlayPause
            )
            // Extra room so the skip discs read as separate targets rather than
            // one crowded cluster around play/pause.
            .padding(.horizontal, 20)

            circleButton(
                L10n.string("player.forward"),
                systemImage: "goforward.10",
                diameter: 58,
                glyph: 22
            ) { onSkip(10) }

            if canPlayPrevious || canPlayNext {
                circleButton(
                    L10n.string("player.next_video"),
                    systemImage: "forward.end.fill",
                    diameter: 44,
                    glyph: 15
                ) { onNext() }
                .disabled(!canPlayNext)
            }
        }
    }

    private func circleButton(
        _ title: String,
        systemImage: String,
        diameter: CGFloat,
        glyph: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyph, weight: .medium))
                // Centring the glyph's bounding box is not the same as centring how
                // it looks: a play triangle is left-heavy, and the arrow-and-numeral
                // skip glyphs sit low. Nudge each back onto the disc's optical centre.
                .offset(
                    x: Self.opticalOffset(for: systemImage).width * glyph,
                    y: Self.opticalOffset(for: systemImage).height * glyph
                )
                // Keeps the glyph readable when the disc happens to sit over a
                // bright frame, without needing to make the disc itself opaque.
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Every disc keeps the same transparency; size alone marks the primary.
        // Tinting it lighter turned it opaque grey and broke that consistency.
        .glazeGlassCircle(.transport)
        .accessibilityLabel(title)
        .help(title)
    }

    /// Optical corrections expressed as a fraction of the glyph's point size, so
    /// they hold at every disc size.
    private static func opticalOffset(for systemImage: String) -> CGSize {
        switch systemImage {
        case "play.fill": CGSize(width: 0.09, height: 0)
        case "backward.end.fill": CGSize(width: -0.03, height: 0)
        case "forward.end.fill": CGSize(width: 0.03, height: 0)
        case "gobackward.10", "goforward.10": CGSize(width: 0, height: -0.03)
        default: .zero
        }
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    if let contextLine {
                        Text(contextLine)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                accessoryCluster
            }

            scrubber
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 20)
    }

    private var accessoryCluster: some View {
        HStack(spacing: 4) {
            // Fixed icon rather than the status glyph: the status glyph is "sparkles"
            // while waiting to generate, which collided with the generate button.
            pillButton(subtitleStatusTitle, systemImage: "captions.bubble", action: onOpenSubtitles)

            if hasSubtitles {
                pillButton(
                    L10n.string(areSubtitlesVisible ? "subtitle.visibility.hide" : "subtitle.visibility.show"),
                    systemImage: areSubtitlesVisible ? "eye.fill" : "eye.slash",
                    isOn: areSubtitlesVisible,
                    action: onToggleSubtitles
                )
            } else {
                pillButton(
                    L10n.string("subtitle.generate"),
                    systemImage: "sparkles",
                    action: onGenerateSubtitles
                )
            }

            pillButton(
                L10n.string("player.full_screen"),
                systemImage: "arrow.up.left.and.arrow.down.right",
                action: onToggleFullScreen
            )
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .glazeGlass(.floating, cornerRadius: 999)
    }

    private func pillButton(
        _ title: String,
        systemImage: String,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? GlazeGlass.amber : .white.opacity(0.86))
        .accessibilityLabel(title)
        .help(title)
    }

    private var scrubber: some View {
        HStack(spacing: 12) {
            Text(formattedTime(displayedTime))
                .frame(width: 46, alignment: .leading)

            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { seekPosition = $0 }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: handleSeeking
            )
            .tint(.white)

            Text("−\(formattedTime(max(duration - displayedTime, 0)))")
                .frame(width: 52, alignment: .trailing)
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.72))
    }

    // MARK: - Helpers

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
