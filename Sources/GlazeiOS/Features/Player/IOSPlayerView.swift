import AVKit
import GlazeCore
import SwiftUI
import UIKit

/// What plays after this one, when there is one.
struct IOSUpNext {
    let title: String
    let play: () -> Void
}

/// Full-screen playback with controls that get out of the way.
struct IOSPlayerView: View {
    let resource: NetworkMediaResource
    let title: String
    var startAt: TimeInterval = 0
    var subtitleURL: URL?
    /// Every subtitle in the film's folder, asked for only when the viewer opens the
    /// picker — listing a folder is a network round trip.
    var subtitleCandidates: (@Sendable () async -> [IOSSubtitleCandidate])?
    var upNext: IOSUpNext?

    @Environment(\.dismiss) private var dismiss
    @Environment(IOSUserPreferences.self) private var preferences
    @State private var model = IOSPlaybackModel()
    @State private var showsControls = true
    @State private var isLocked = false
    @State private var showsSettings = false
    @State private var hideTask: Task<Void, Never>?

    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var gesture = PlayerGestureState()

    private var displayedTime: TimeInterval { isScrubbing ? scrubTime : model.currentTime }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            IOSVideoSurface(player: model.player).ignoresSafeArea()

            if model.hasFailed {
                failure
            } else if model.isBuffering {
                ProgressView().controlSize(.large).tint(.white)
            }

            if isLocked {
                lockedOverlay
            } else if showsControls {
                controls.transition(.opacity)
            }

            if let hud = gesture.hud {
                gestureHUD(hud)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { isLocked ? revealLock() : revealControls() }
        .gesture(playbackGesture)
        .animation(.easeOut(duration: 0.2), value: showsControls)
        .animation(.easeOut(duration: 0.2), value: isLocked)
        .sheet(isPresented: $showsSettings) {
            IOSPlayerSettingsView(model: model, subtitleCandidates: subtitleCandidates)
                .environment(preferences)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            model.start(
                resource,
                title: title,
                at: startAt,
                subtitleURL: subtitleURL,
                preferences: preferences
            )
            revealControls()
        }
        .onDisappear {
            hideTask?.cancel()
            model.stop()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            transport
            timeline
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            circleButton("chevron.down") { dismiss() }

            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            circleButton("lock.open") { isLocked = true; showsControls = false }
            circleButton(model.isFillingScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                model.setFillingScreen(!model.isFillingScreen)
                revealControls()
            }
            rateMenu
            circleButton("captions.bubble") { showsSettings = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var rateMenu: some View {
        Menu {
            Picker(L10n.string("ios.player.rate"), selection: rateBinding) {
                ForEach(IOSPlaybackModel.rateOptions, id: \.self) { option in
                    Text(Self.rateLabel(option)).tag(option)
                }
            }
        } label: {
            Text(Self.rateLabel(model.rate))
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(minWidth: 34)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45), in: Capsule())
        }
    }

    private var rateBinding: Binding<Float> {
        Binding(get: { model.rate }, set: { newValue in
            model.setRate(newValue)
            preferences.playbackRate = newValue
            revealControls()
        })
    }

    private var transport: some View {
        HStack(spacing: 44) {
            Button { model.skip(by: -IOSPlaybackModel.skipInterval); revealControls() } label: {
                Image(systemName: "gobackward.10").font(.title)
            }
            Button { model.togglePlayback(); revealControls() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
            }
            Button { model.skip(by: IOSPlaybackModel.skipInterval); revealControls() } label: {
                Image(systemName: "goforward.10").font(.title)
            }
        }
        .padding(.bottom, 18)
    }

    private var timeline: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(model.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                        scrubTime = model.currentTime
                        hideTask?.cancel()
                    } else {
                        isScrubbing = false
                        model.seek(to: scrubTime)
                        revealControls()
                    }
                }
            )
            .tint(IOSTheme.amber)
            .disabled(model.duration <= 0)

            HStack {
                Text(Self.timecode(displayedTime))
                Spacer()
                if let upNext {
                    Button {
                        model.stop()
                        upNext.play()
                    } label: {
                        Label(L10n.string("ios.player.next"), systemImage: "forward.end.fill")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                Text(Self.timecode(model.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Locked, failed, HUD

    /// A phone in a pocket or a hand at the wrong angle should not scrub a film. The
    /// lock stays visible for a moment after a tap so it can be undone.
    private var lockedOverlay: some View {
        VStack {
            HStack {
                Spacer()
                if showsControls {
                    Button { isLocked = false; revealControls() } label: {
                        Image(systemName: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            Spacer()
        }
    }

    private var failure: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(IOSTheme.amber)
            Text(L10n.string("ios.player.failed"))
                .font(.callout)
                .foregroundStyle(.white)
            Button(L10n.string("common.close")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(IOSTheme.amber)
        }
        .padding(28)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
    }

    private func gestureHUD(_ hud: PlayerGestureState.HUD) -> some View {
        Label(hud.text, systemImage: hud.symbol)
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.6), in: Capsule())
    }

    // MARK: - Gestures

    /// Drag sideways to scrub, up and down for brightness on the left of the screen and
    /// volume on the right — what every video app on this platform does, and what
    /// people try first.
    private var playbackGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isLocked else { return }
                switch gesture.axis(for: value.translation) {
                case .horizontal:
                    if !isScrubbing {
                        isScrubbing = true
                        scrubTime = model.currentTime
                        gesture.anchor = model.currentTime
                        hideTask?.cancel()
                        showsControls = true
                    }
                    let span = max(model.duration, 60)
                    let seconds = gesture.anchor + Double(value.translation.width / 320) * min(span, 600)
                    scrubTime = min(max(seconds, 0), max(model.duration, 1))
                    gesture.hud = .init(
                        symbol: value.translation.width < 0 ? "backward.fill" : "forward.fill",
                        text: Self.timecode(scrubTime)
                    )
                case .vertical:
                    let delta = Double(-value.translation.height / 260)
                    if value.startLocation.x < UIScreen.main.bounds.width / 2 {
                        gesture.applyBrightness(delta)
                    } else {
                        gesture.applyVolume(delta)
                    }
                }
            }
            .onEnded { _ in
                guard !isLocked else { return }
                if isScrubbing {
                    isScrubbing = false
                    model.seek(to: scrubTime)
                    revealControls()
                }
                gesture.end()
            }
    }

    // MARK: - Chrome timing

    /// Controls appear on a tap and leave again on their own; a film with a bar across
    /// it is not what anyone came to watch.
    private func revealControls() {
        showsControls = true
        scheduleHide()
    }

    private func revealLock() {
        showsControls = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            showsControls = false
        }
    }

    private static func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? String(format: "%.0f×", rate) : String(format: "%.2g×", rate)
    }

    static func timecode(_ seconds: TimeInterval) -> String {
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

/// Which way a drag went, and what it did — kept out of the view so the gesture body
/// stays readable.
@Observable
@MainActor
final class PlayerGestureState {
    struct HUD: Equatable {
        let symbol: String
        let text: String
    }

    enum Axis { case horizontal, vertical }

    var hud: HUD?
    var anchor: TimeInterval = 0
    private var lockedAxis: Axis?

    func axis(for translation: CGSize) -> Axis {
        if let lockedAxis { return lockedAxis }
        let axis: Axis = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
        lockedAxis = axis
        return axis
    }

    func applyBrightness(_ delta: Double) {
        let level = min(max(UIScreen.main.brightness + delta * 0.06, 0), 1)
        UIScreen.main.brightness = level
        hud = HUD(symbol: "sun.max.fill", text: "\(Int(level * 100))%")
    }

    func applyVolume(_ delta: Double) {
        let level = SystemVolume.adjust(by: Float(delta) * 0.06)
        hud = HUD(symbol: level > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill", text: "\(Int(level * 100))%")
    }

    func end() {
        lockedAxis = nil
        hud = nil
    }
}
