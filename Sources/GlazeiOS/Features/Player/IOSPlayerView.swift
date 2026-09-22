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
    /// The films around this one — the rest of the folder, in order. With it, the
    /// player can go back and forward and show what else is there; without it, it plays
    /// one film and stops, which is what it always did.
    var queue: PlaybackQueue?

    @Environment(\.dismiss) private var dismiss
    @Environment(IOSUserPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = IOSPlaybackModel()
    @State private var showsControls = true
    @State private var isLocked = false
    @State private var showsSettings = false
    @State private var hideTask: Task<Void, Never>?
    /// Whether the viewer asked for landscape, as opposed to having turned the phone.
    @State private var isHoldingLandscape = false
    /// The queue as it moves. Copied from `queue` once, because the view's own
    /// parameter cannot change while the film plays.
    @State private var playlist: PlaybackQueue?
    /// What is on screen now. Starts as the film this view was opened with and changes
    /// when the viewer moves through the folder.
    @State private var nowPlaying: PlaybackQueueItem?
    @State private var showsPlaylist = false

    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var gesture = PlayerGestureState()
    /// The still shown above the timeline while a thumb drags along it.
    @State private var preview = ScrubPreviewLoader(source: nil)
    /// Clears the double-tap mark once it has been seen.
    @State private var hudTask: Task<Void, Never>?

    private var displayedTime: TimeInterval { isScrubbing ? scrubTime : model.currentTime }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // VLC draws into a UIKit view of its own making, and that view swallowed
            // every touch that reached it. While the controls were on screen they
            // covered it and nothing looked wrong; once they hid, the film itself was
            // the only thing under the finger and tapping did nothing at all — there
            // was no way back to the controls short of closing the film.
            //
            // The picture is not a control, so it does not take touches. They belong
            // to the transparent layer below, which is SwiftUI's and spans the whole
            // screen including under the notch and the home indicator.
            IOSVideoSurface(player: model.player)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            touchLayer

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
        // Someone who has asked for less movement should not have the chrome slide
        // in and out over the film.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsControls)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isLocked)
        // Pausing suppresses the hide; playing again has to start it.
        .onChange(of: model.isPlaying) { _, playing in
            if playing { scheduleHide() } else { hideTask?.cancel() }
        }
        .sheet(isPresented: $showsPlaylist) {
            if let playlist {
                IOSPlaylistSheet(
                    queue: playlist,
                    positions: PlaybackPositionStore(),
                    onChoose: { id in
                        showsPlaylist = false
                        jump(to: id)
                    }
                )
                .presentationDetents([PresentationDetent.medium, .large])
            }
        }
        .sheet(isPresented: $showsSettings) {
            IOSPlayerSettingsView(model: model, subtitleCandidates: subtitleCandidates)
                .environment(preferences)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            let first = PlaybackQueueItem(resource: resource, title: title)
            nowPlaying = first
            playlist = queue.map { PlaybackQueue(items: $0.items, current: first) }
            wireQueue()
            model.start(
                resource,
                title: title,
                at: startAt,
                subtitleURL: subtitleURL,
                preferences: preferences
            )
            revealControls()
            preview = ScrubPreviewLoader(
                source: VLCScrubPreviewSource(url: resource.playbackURL)
            )
        }
        .onDisappear {
            hideTask?.cancel()
            model.stop()
            if isHoldingLandscape { IOSScreenOrientation.release() }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        ZStack {
            // Under the buttons and over the film. While the chrome is up it covers
            // the picture, so a tap on its empty half reached nothing at all — which
            // is why tapping again did not put it away.
            touchLayer
            controlStack
        }
    }

    private var controlStack: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            transport
            timeline
                .padding(.horizontal, IOSTheme.Spacing.large)
                .padding(.bottom, IOSTheme.Spacing.large)
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

    /// Controls on one line, the title on its own beneath.
    ///
    /// The title used to sit between the close button and the rest, and with seven
    /// controls on a 402pt screen it was down to a single character — "엉" for
    /// 엉뚱한 영화, which tells the viewer nothing. A film's name is not a control and
    /// does not have to share the row with them.
    private var topBar: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.small) {
            HStack(spacing: IOSTheme.Spacing.tight) {
                circleButton("chevron.down", label: L10n.string("ios.player.a11y.close")) { dismiss() }

                Spacer(minLength: 0)

                circleButton("lock.open", label: L10n.string("ios.player.a11y.lock")) {
                    isLocked = true
                    showsControls = false
                }
                circleButton(
                    model.isFillingScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: L10n.string(model.isFillingScreen ? "ios.player.a11y.fit" : "ios.player.a11y.fill")
                ) {
                    model.setFillingScreen(!model.isFillingScreen)
                    revealControls()
                }
                circleButton(
                    orientationSymbol,
                    label: L10n.string(isHoldingLandscape ? "ios.player.a11y.portrait" : "ios.player.a11y.landscape")
                ) {
                    toggleLandscape()
                    revealControls()
                }
                rateMenu
                if playlist?.isNavigable == true {
                    circleButton("list.bullet", label: L10n.string("ios.player.playlist")) {
                        showsPlaylist = true
                    }
                }
                circleButton("captions.bubble", label: L10n.string("ios.player.settings")) {
                    showsSettings = true
                }
            }

            Text(nowPlaying?.title ?? title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, IOSTheme.Spacing.tight)
        }
        .padding(.horizontal, IOSTheme.Spacing.medium)
        .padding(.top, IOSTheme.Spacing.small)
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
                .padding(.vertical, IOSTheme.Spacing.tight)
                .padding(.horizontal, IOSTheme.Spacing.small)
                .glazeTransportDisc(Capsule())
                .touchTarget()
        }
        .accessibilityLabel(L10n.string("ios.player.rate"))
        .accessibilityValue(Self.rateLabel(model.rate))
    }

    private var rateBinding: Binding<Float> {
        Binding(get: { model.rate }, set: { newValue in
            model.setRate(newValue)
            preferences.playbackRate = newValue
            revealControls()
        })
    }

    private var transport: some View {
        // Wider than any gap on the scale, deliberately: the three transport
        // controls are hit in the dark and must not be neighbours.
        HStack(spacing: hasQueue ? 20 : 44) {
            // Outside the skips, the order every player uses — and the order the
            // approved Mac transport uses, so the two read as one product.
            if hasQueue {
                Button { goBack(); revealControls() } label: {
                    transportGlyph("backward.end.fill", diameter: 44, glyph: 18)
                }
                .accessibilityLabel(L10n.string("ios.player.a11y.previous"))
            }

            Button { model.skip(by: -IOSPlaybackModel.skipInterval); revealControls() } label: {
                transportGlyph("gobackward.10", diameter: 52, glyph: 24)
            }
            .accessibilityLabel(L10n.string("ios.player.a11y.back"))

            Button { model.togglePlayback(); revealControls() } label: {
                // One step larger, and only larger: the contract asks for size to mark
                // the primary control, not a different colour or weight.
                transportGlyph(model.isPlaying ? "pause.fill" : "play.fill", diameter: 68, glyph: 30)
            }
            .accessibilityLabel(L10n.string(model.isPlaying ? "ios.player.a11y.pause" : "ios.player.a11y.play"))

            Button { model.skip(by: IOSPlaybackModel.skipInterval); revealControls() } label: {
                transportGlyph("goforward.10", diameter: 52, glyph: 24)
            }
            .accessibilityLabel(L10n.string("ios.player.a11y.forward"))

            if hasQueue {
                Button { goForward(); revealControls() } label: {
                    transportGlyph("forward.end.fill", diameter: 44, glyph: 18)
                }
                // Dimmed rather than hidden at the last film, so the row does not
                // shift under a thumb that was about to press it.
                .disabled(playlist?.next == nil)
                .opacity(playlist?.next == nil ? 0.4 : 1)
                .accessibilityLabel(L10n.string("ios.player.a11y.next"))
            }
        }
        .padding(.bottom, IOSTheme.Spacing.large)
    }

    /// The three transport controls were bare glyphs relying on the gradient behind
    /// them, which the acceptance criteria rule out: they have to stay identifiable
    /// over a bright frame. Discs, separate, never a shared capsule.
    private func transportGlyph(_ symbol: String, diameter: CGFloat, glyph: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: glyph, weight: .medium))
            .frame(width: diameter, height: diameter)
            .glazeTransportDisc()
    }

    private var timeline: some View {
        VStack(spacing: IOSTheme.Spacing.hair) {
            scrubPreview
            IOSTimelineBar(
                duration: max(model.duration, 0),
                value: Binding(
                    get: { displayedTime },
                    set: { scrubTime = $0 }
                ),
                onScrubbingChanged: { scrubbing in
                    if scrubbing {
                        isScrubbing = true
                        hideTask?.cancel()
                    } else {
                        isScrubbing = false
                        model.seek(to: scrubTime)
                        revealControls()
                    }
                }
            )
            .disabled(model.duration <= 0)
            .onChange(of: scrubTime) { _, time in
                guard isScrubbing else { return }
                preview.request(time)
            }
            .onChange(of: isScrubbing) { _, scrubbing in
                if scrubbing { preview.request(scrubTime) } else { preview.clear() }
            }
            .accessibilityLabel(L10n.string("ios.player.a11y.timeline"))
            .accessibilityValue(Self.timecode(displayedTime))

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
                            .touchTarget()
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

    /// The frame under the thumb, above the timeline.
    ///
    /// Held in place rather than following the thumb along the bar: on a phone the
    /// thumb is on the bar, and a picture that tracked it would spend half the film
    /// under the hand holding the phone.
    @ViewBuilder
    private var scrubPreview: some View {
        if isScrubbing, preview.isAvailable {
            ZStack {
                RoundedRectangle(cornerRadius: IOSTheme.Radius.card, style: .continuous)
                    .fill(.black.opacity(0.6))
                if let frame = preview.frame, let image = UIImage(data: frame) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: IOSTheme.Radius.card, style: .continuous))
                } else {
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
            .frame(width: 176, height: 99)
            .overlay(alignment: .bottom) {
                Text(Self.timecode(scrubTime))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, IOSTheme.Spacing.small)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, IOSTheme.Spacing.tight)
            }
            .overlay(
                RoundedRectangle(cornerRadius: IOSTheme.Radius.card, style: .continuous)
                    .stroke(.white.opacity(0.18))
            )
            .padding(.bottom, IOSTheme.Spacing.small)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    /// The glyph stays small — a bar across a film should be quiet — but the target
    /// under it is a thumb's width.
    private func circleButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .glazeTransportDisc()
                .touchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
                            .glazeTransportDisc()
                            .touchTarget()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel(L10n.string("ios.player.a11y.unlock"))
                }
            }
            .padding(.horizontal, IOSTheme.Spacing.medium)
            .padding(.top, IOSTheme.Spacing.medium)
            Spacer()
        }
    }

    private var failure: some View {
        VStack(spacing: IOSTheme.Spacing.medium) {
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
        .padding(IOSTheme.Spacing.section)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
    }

    private func gestureHUD(_ hud: PlayerGestureState.HUD) -> some View {
        Label(hud.text, systemImage: hud.symbol)
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, IOSTheme.Spacing.large)
            .padding(.vertical, IOSTheme.Spacing.small)
            .glazeTransportDisc(Capsule())
    }

    // MARK: - Gestures

    /// Everything a finger can do to the picture: a tap to show or put away the
    /// controls, a double tap on either side to jump ten seconds, and a drag to
    /// scrub, or to move brightness and volume.
    private var touchLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            // Declared before the single tap so that one waits to see whether a
            // second is coming — which is how every video app behaves.
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                guard !isLocked else { return }
                skip(tappedAt: location)
            }
            .onTapGesture { isLocked ? revealLock() : toggleControls() }
            .gesture(playbackGesture)
    }

    /// Ten seconds back or forward depending on which half was tapped, without
    /// bringing the controls up for it.
    private func skip(tappedAt location: CGPoint) {
        let isForward = location.x > UIScreen.main.bounds.width / 2
        let interval = isForward ? IOSPlaybackModel.skipInterval : -IOSPlaybackModel.skipInterval
        model.skip(by: interval)
        gesture.hud = .init(
            symbol: isForward ? "goforward.10" : "gobackward.10",
            text: Self.timecode(max(model.currentTime + interval, 0))
        )
        // The mark answers the tap; it is not a state, so it goes on its own.
        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            gesture.hud = nil
        }
    }

    /// Drag sideways to scrub, up and down for brightness on the left of the screen and
    /// volume on the right — what every video app on this platform does, and what
    /// people try first.
    /// How far a finger travels for the full range of brightness or volume — more
    /// than a phone screen is tall. Both ends are still reachable in one drag from
    /// the middle, and nothing else about a film needs a whole screen of travel, so
    /// the scale is better spent on control than on speed.
    private static let verticalGestureTravel: CGFloat = 1_000

    /// Movement before either one starts to shift, on top of the 12pt the gesture
    /// itself waits for. Someone dragging sideways to scrub drifts vertically while
    /// they do it, and without this the volume moved every time.
    private static let verticalGestureDeadZone: CGFloat = 16

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
                    // Measured from where the finger went down, against a travel of
                    // most of the screen. Each event used to add a step to whatever
                    // the level already was, so holding still at the bottom of a drag
                    // kept driving it — a flick took the volume from half to full.
                    let height = value.translation.height
                    let beyondDeadZone = max(abs(height) - Self.verticalGestureDeadZone, 0)
                    let travel = Double(-(height < 0 ? -beyondDeadZone : beyondDeadZone) / Self.verticalGestureTravel)
                    if value.startLocation.x < UIScreen.main.bounds.width / 2 {
                        gesture.setBrightness(travel)
                    } else {
                        gesture.setVolume(travel)
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
    // MARK: - Moving through the folder

    private var hasQueue: Bool { playlist?.isNavigable == true }

    /// The lock screen, AirPods and the end of a film all move through the same queue
    /// the on-screen buttons do.
    private func wireQueue() {
        guard hasQueue else { return }
        model.onFinished = { goForward() }
        model.onNextTrack = { goForward() }
        model.onPreviousTrack = { goBack() }
    }

    /// At the end of the folder this does nothing — whether the film ended by itself or
    /// the button was pressed. Wrapping round to the first episode is not what a person
    /// who just finished the last one wants.
    private func goForward() {
        guard var queue = playlist, let next = queue.advance() else { return }
        playlist = queue
        play(next)
    }

    /// Restart the film first, and only go back a file from its opening seconds — what
    /// every player people use does. Jumping to the last episode from minute forty is
    /// almost never what was meant.
    private func goBack() {
        if model.currentTime > PlaybackQueue.restartThreshold {
            model.seek(to: 0)
            return
        }
        guard var queue = playlist, let previous = queue.retreat() else {
            model.seek(to: 0)
            return
        }
        playlist = queue
        play(previous)
    }

    private func jump(to id: String) {
        guard var queue = playlist, id != nowPlaying?.id, let item = queue.jump(to: id) else { return }
        playlist = queue
        play(item)
    }

    /// Swaps the film in place. The player stays on screen — closing and reopening it
    /// for every episode would flash back to the list and lose the orientation.
    private func play(_ item: PlaybackQueueItem) {
        model.stop()
        nowPlaying = item
        wireQueue()
        model.start(
            item.resource,
            title: item.title,
            at: 0,
            // Only when the viewer asked for subtitles to be picked for them. Passing no
            // language here would not mean "none" — it falls back to a default.
            subtitleURL: preferences.automaticallySelectSubtitles
                ? IOSSubtitleChoice.preferred(
                    among: item.resource.subtitleResources,
                    language: preferences.defaultSubtitleLanguageCode
                )
                : nil,
            preferences: preferences
        )
    }

    /// Sideways, and stays there. Released when the film closes, so the rest of the
    /// app is never left locked by a button pressed inside the player.
    private func toggleLandscape() {
        if isHoldingLandscape {
            IOSScreenOrientation.release()
            isHoldingLandscape = false
        } else {
            IOSScreenOrientation.hold(.landscape)
            isHoldingLandscape = true
        }
    }

    /// Shows what the button will do, not what the screen is doing: the icon has to
    /// stay still while the phone is turned by hand.
    private var orientationSymbol: String {
        isHoldingLandscape ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate"
    }

    private func revealControls() {
        showsControls = true
        scheduleHide()
    }

    /// A tap on the film puts the controls away again.
    ///
    /// Tapping while they were up used to only restart the five-second timer, so the
    /// bar someone was trying to dismiss sat there for another five seconds. The rule
    /// itself is `PlayerChromeIntent`, shared and tested.
    private func toggleControls() {
        apply(PlayerChromeIntent.forTap(visible: showsControls, isPlaying: model.isPlaying))
    }

    private func apply(_ intent: PlayerChromeIntent) {
        hideTask?.cancel()
        showsControls = intent.showsControls
        if intent.startsHideTimer { scheduleHide() }
    }

    private func revealLock() {
        showsControls = true
        scheduleHide()
    }

    /// Controls get out of the way of the film — but only while there is a film to be
    /// in the way of. Paused, they stay: someone who has stopped to read a subtitle,
    /// find the settings or turn the screen should not have to tap twice to get the
    /// buttons back to where they were looking.
    private func scheduleHide() {
        hideTask?.cancel()
        guard model.isPlaying else { return }
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
    /// Where brightness and volume stood when the finger went down. Without these the
    /// adjustment compounds: every event reads the level it set a moment ago.
    private var brightnessAnchor: Double?
    private var volumeAnchor: Float?

    func axis(for translation: CGSize) -> Axis {
        if let lockedAxis { return lockedAxis }
        let axis: Axis = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
        lockedAxis = axis
        return axis
    }

    /// - Parameter travel: how far up the screen the finger has come, as a fraction
    ///   of the full range. Applied to where the level started, not to where it is.
    func setBrightness(_ travel: Double) {
        let start = brightnessAnchor ?? Double(UIScreen.main.brightness)
        brightnessAnchor = start
        let level = min(max(start + travel, 0), 1)
        UIScreen.main.brightness = CGFloat(level)
        hud = HUD(symbol: "sun.max.fill", text: "\(Int((level * 100).rounded()))%")
    }

    func setVolume(_ travel: Double) {
        let start = volumeAnchor ?? SystemVolume.level
        volumeAnchor = start
        let level = SystemVolume.set(min(max(start + Float(travel), 0), 1))
        hud = HUD(
            symbol: level > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill",
            text: "\(Int((level * 100).rounded()))%"
        )
    }

    func end() {
        lockedAxis = nil
        brightnessAnchor = nil
        volumeAnchor = nil
        hud = nil
    }
}
