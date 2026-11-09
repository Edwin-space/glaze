import GlazeCore
import SwiftUI

/// The gestures the player has no room to show.
///
/// A double tap, a swipe and a press-and-hold leave no mark on the screen — that is
/// why they are good gestures and why nobody finds them. Shown once over the first
/// film, and after that only when asked for in 설정 › 도움말.
struct IOSGestureGuideView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Over a film the card floats on the picture and carries its own dismissal; in
    /// Settings it is a page and the navigation bar does that job.
    var onDone: (() -> Void)?

    private struct Gesture: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private var gestures: [Gesture] {
        [
            Gesture(
                symbol: "hand.tap",
                title: L10n.string("ios.guide.tap.title"),
                detail: L10n.string("ios.guide.tap.detail")
            ),
            Gesture(
                symbol: "hand.tap.fill",
                title: L10n.string("ios.guide.double_tap.title"),
                detail: L10n.string("ios.guide.double_tap.detail")
            ),
            Gesture(
                symbol: "hand.draw",
                title: L10n.string("ios.guide.swipe.title"),
                detail: L10n.string("ios.guide.swipe.detail")
            ),
            Gesture(
                symbol: "forward.fill",
                title: L10n.string("ios.guide.hold.title"),
                detail: L10n.string("ios.guide.hold.detail")
            ),
            Gesture(
                symbol: "timeline.selection",
                title: L10n.string("ios.guide.scrub.title"),
                detail: L10n.string("ios.guide.scrub.detail")
            )
        ]
    }

    var body: some View {
        Group {
            if let onDone {
                VStack(spacing: 0) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        guideTitle
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(IOSTheme.Spacing.large)
                    }
                    ScrollView {
                        if dynamicTypeSize.isAccessibilitySize {
                            // A large heading must not consume the entire short
                            // landscape viewport. Keep it readable in the scroll
                            // content rather than shrinking or truncating it.
                            guideContents.padding(IOSTheme.Spacing.large)
                        } else {
                            gestureRows
                                .padding(.horizontal, IOSTheme.Spacing.large)
                                .padding(.bottom, IOSTheme.Spacing.large)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("player.gestureGuide.content")
                    Divider()
                    Button(action: onDone) {
                        Text(L10n.string("ios.guide.got_it"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(IOSTheme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: IOSTheme.minimumTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(IOSTheme.amber)
                    .accessibilityIdentifier("player.gestureGuide.done")
                    .padding(IOSTheme.Spacing.large)
                }
                .frame(maxHeight: .infinity)
            } else {
                guideContents.padding(IOSTheme.Spacing.large)
            }
        }
        .frame(maxWidth: 420)
    }

    private var guideContents: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.large) {
            guideTitle
            gestureRows
        }
    }

    private var guideTitle: some View {
        Text(L10n.string("ios.guide.title"))
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("player.gestureGuide.title")
    }

    private var gestureRows: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.large) {
            ForEach(gestures) { gesture in
                HStack(alignment: .top, spacing: IOSTheme.Spacing.medium) {
                    Image(systemName: gesture.symbol)
                        .font(.body)
                        .foregroundStyle(IOSTheme.amber)
                        .frame(width: 28, alignment: .center)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: IOSTheme.Spacing.hair) {
                        Text(gesture.title).font(.subheadline.weight(.medium))
                        Text(gesture.detail)
                            .font(.footnote)
                            .foregroundStyle(IOSTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

        }
    }
}

/// The same card, as a page in Settings.
struct IOSGestureGuidePage: View {
    var body: some View {
        ScrollView {
            IOSGestureGuideView()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(IOSTheme.ground.ignoresSafeArea())
        .navigationTitle(L10n.string("ios.guide.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
