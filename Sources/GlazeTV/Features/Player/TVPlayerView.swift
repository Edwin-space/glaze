import GlazeCore
import SwiftUI

/// Watching one film, from the sofa.
///
/// The video stays visually dominant. Playback controls are separated into a timeline
/// and a compact transport row instead of sitting inside one large opaque panel. The
/// timeline is a focused tvOS scrubber, so the Siri Remote touch surface can seek precisely.
struct TVPlayerView: View {
    let resource: NetworkMediaResource
    let title: String
    var startAt: TimeInterval = 0
    var externalSubtitleURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var model = TVPlaybackModel()
    @State private var areControlsVisible = true
    @State private var isShowingSubtitleSettings = false
    @State private var scrubTime: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var focusedControl: FocusTarget?

    private enum FocusTarget: Hashable {
        case surface
        case timeline
        case rewind
        case playPause
        case forward
        case subtitles
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVVideoSurface(player: model.player).ignoresSafeArea()

            if model.hasFailed {
                failure
            } else {
                interactionSurface

                if areControlsVisible {
                    controls.transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if isShowingSubtitleSettings {
                    subtitleSettings.transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            model.start(resource, at: startAt, subtitleURL: externalSubtitleURL)
            scrubTime = startAt
            focusedControl = .timeline
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            model.rememberPosition(for: resource)
            model.stop()
        }
        .onExitCommand {
            if isShowingSubtitleSettings {
                closeSubtitleSettings()
            } else {
                dismiss()
            }
        }
        .onPlayPauseCommand { toggle() }
        .onChange(of: model.currentTime) { _, currentTime in
            if !isScrubbing {
                scrubTime = currentTime
            }
        }
        .onChange(of: focusedControl) { _, _ in
            if areControlsVisible, !isShowingSubtitleSettings {
                scheduleHide()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: areControlsVisible)
        .animation(.easeInOut(duration: 0.22), value: isShowingSubtitleSettings)
    }

    /// When controls are hidden, the whole picture receives the first remote action.
    /// A click reveals the timeline; left and right retain the familiar ten-second skip.
    @ViewBuilder
    private var interactionSurface: some View {
        if !areControlsVisible, !isShowingSubtitleSettings {
            Color.clear
                .contentShape(Rectangle())
                .focusable()
                .focused($focusedControl, equals: .surface)
                .onTapGesture { reveal(focus: .timeline) }
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        model.skip(-TVPlaybackModel.skipInterval)
                        reveal(focus: .rewind)
                    case .right:
                        model.skip(TVPlaybackModel.skipInterval)
                        reveal(focus: .forward)
                    default:
                        reveal(focus: .timeline)
                    }
                }
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            Spacer()

            LinearGradient(
                colors: [.clear, .black.opacity(0.36), .black.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 430)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title)
                        .font(.system(size: 34, weight: .semibold))
                        .lineLimit(1)

                    timeline
                    transport
                }
                .padding(.horizontal, 76)
                .padding(.bottom, 52)
            }
        }
        .ignoresSafeArea()
    }

    private var timeline: some View {
        VStack(spacing: 8) {
            TVScrubber(
                value: $scrubTime,
                range: 0...max(model.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        hideTask?.cancel()
                    } else {
                        model.seek(to: scrubTime)
                        scheduleHide()
                    }
                }
            )
            .frame(height: 48)
            .focused($focusedControl, equals: .timeline)

            HStack {
                Text(timecode(scrubTime))
                Spacer()
                Text("−\(timecode(max(model.duration - scrubTime, 0)))")
            }
            .font(.system(size: 23, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var transport: some View {
        HStack(spacing: 20) {
            transportButton(
                systemName: "gobackward.10",
                accessibilityLabel: L10n.string("tv.player.rewind_10"),
                focus: .rewind
            ) {
                model.skip(-TVPlaybackModel.skipInterval)
                reveal(focus: .rewind)
            }

            transportButton(
                systemName: model.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: L10n.string(model.isPlaying ? "tv.player.pause" : "tv.player.play"),
                emphasized: true,
                focus: .playPause
            ) {
                toggle()
            }

            transportButton(
                systemName: "goforward.10",
                accessibilityLabel: L10n.string("tv.player.forward_10"),
                focus: .forward
            ) {
                model.skip(TVPlaybackModel.skipInterval)
                reveal(focus: .forward)
            }

            Spacer()

            Button {
                openSubtitleSettings()
            } label: {
                Label(L10n.string("tv.player.subtitles"), systemImage: "captions.bubble")
                    .font(.system(size: 25, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 64)
            }
            .buttonStyle(.bordered)
            .tint(model.selectedSubtitleTrackID == nil ? .white.opacity(0.16) : TVTheme.amber)
            .focused($focusedControl, equals: .subtitles)
        }
    }

    private func transportButton(
        systemName: String,
        accessibilityLabel: String,
        emphasized: Bool = false,
        focus: FocusTarget,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: emphasized ? 33 : 29, weight: .semibold))
                .frame(width: emphasized ? 76 : 64, height: emphasized ? 76 : 64)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(emphasized ? TVTheme.amber : .white.opacity(0.16))
        .focused($focusedControl, equals: focus)
        .accessibilityLabel(accessibilityLabel)
    }

    private var subtitleSettings: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { closeSubtitleSettings() }

            TVSubtitleSettingsPanel(model: model, onClose: closeSubtitleSettings)
                .frame(width: 650)
                .background(.ultraThinMaterial)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                }
                .ignoresSafeArea()
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

    private func toggle() {
        model.togglePlayPause()
        reveal(focus: .playPause)
    }

    private func reveal(focus: FocusTarget) {
        areControlsVisible = true
        focusedControl = focus
        scheduleHide()
    }

    private func openSubtitleSettings() {
        hideTask?.cancel()
        areControlsVisible = true
        isShowingSubtitleSettings = true
    }

    private func closeSubtitleSettings() {
        isShowingSubtitleSettings = false
        focusedControl = .subtitles
        scheduleHide()
    }

    private func scheduleHide() {
        guard !isShowingSubtitleSettings, !isScrubbing else { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            areControlsVisible = false
            focusedControl = .surface
        }
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

private struct TVSubtitleSettingsPanel: View {
    @Bindable var model: TVPlaybackModel
    let onClose: () -> Void

    private let sizeOptions: [(key: String, scale: Float)] = [
        ("subtitle.appearance.size.small", 85),
        ("subtitle.appearance.size.medium", 100),
        ("subtitle.appearance.size.large", 125),
        ("subtitle.appearance.size.extra_large", 150)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.string("tv.player.subtitle.settings"))
                    .font(.system(size: 38, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L10n.string("network.browser.close"))
            }
            .padding(.horizontal, 42)
            .padding(.top, 52)
            .padding(.bottom, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    trackSection
                    Divider().overlay(.white.opacity(0.18))
                    syncSection
                    Divider().overlay(.white.opacity(0.18))
                    sizeSection
                }
                .padding(.horizontal, 42)
                .padding(.bottom, 60)
            }
        }
    }

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.string("tv.player.subtitle.track"))

            selectionButton(
                title: L10n.string("tv.player.subtitle.off"),
                isSelected: model.selectedSubtitleTrackID == nil
            ) {
                model.disableSubtitles()
            }

            if model.subtitleTracks.isEmpty {
                Text(L10n.string("tv.player.subtitle.none"))
                    .font(.system(size: 23))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.vertical, 12)
            } else {
                ForEach(model.subtitleTracks) { track in
                    selectionButton(title: track.title, isSelected: track.isSelected) {
                        model.selectSubtitleTrack(id: track.id)
                    }
                }
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.string("tv.player.subtitle.sync"))
            HStack(spacing: 16) {
                Button { model.adjustSubtitleDelay(by: -0.5) } label: {
                    Image(systemName: "minus")
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)

                Text(String(format: L10n.string("tv.player.subtitle.sync_format"), model.subtitleDelay))
                    .font(.system(size: 27, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)

                Button { model.adjustSubtitleDelay(by: 0.5) } label: {
                    Image(systemName: "plus")
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }
        }
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.string("subtitle.appearance.size"))
            ForEach(sizeOptions, id: \.key) { option in
                selectionButton(
                    title: L10n.string(option.key),
                    isSelected: abs(model.subtitleScale - option.scale) < 1
                ) {
                    model.setSubtitleScale(option.scale)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private func selectionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 27, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(TVTheme.amber)
                }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        }
        .buttonStyle(.card)
    }
}
