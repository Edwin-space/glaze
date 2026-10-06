import GlazeCore
import SwiftUI

/// What this app is, once, on the first launch.
///
/// A player opened for the first time shows an empty folder and a tab called 네트워크,
/// and nothing on the screen says how a film gets in. That is not a thing to discover
/// by experiment: the two ways in — the Files app and a server on the same network —
/// each take a step outside Glaze.
///
/// Four lines and a button. Not a tour, not a carousel, and nothing that has to be
/// paged through before the app can be used. Reachable again from 설정 › 도움말, so
/// skipping it costs nothing.
struct IOSWelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: IOSTheme.Spacing.section) {
                    header

                    VStack(alignment: .leading, spacing: IOSTheme.Spacing.large) {
                        point(
                            symbol: "iphone.and.arrow.forward",
                            title: L10n.string("ios.welcome.files.title"),
                            detail: L10n.string("ios.welcome.files.detail")
                        )
                        point(
                            symbol: "externaldrive.connected.to.line.below",
                            title: L10n.string("ios.welcome.network.title"),
                            detail: L10n.string("ios.welcome.network.detail")
                        )
                        point(
                            symbol: "captions.bubble",
                            title: L10n.string("ios.welcome.subtitles.title"),
                            detail: L10n.string("ios.welcome.subtitles.detail")
                        )
                        point(
                            symbol: "hand.tap",
                            title: L10n.string("ios.welcome.gestures.title"),
                            detail: L10n.string("ios.welcome.gestures.detail")
                        )
                    }

                    Text(L10n.string("ios.welcome.privacy"))
                        .font(.footnote)
                        .foregroundStyle(IOSTheme.dim)
                }
                .padding(IOSTheme.Spacing.large)
            }
            .background(IOSTheme.ground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text(L10n.string("ios.welcome.start"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: IOSTheme.minimumTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(IOSTheme.amber)
                .padding(IOSTheme.Spacing.large)
                .background(.ultraThinMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.small) {
            Text(L10n.string("ios.welcome.title"))
                .font(.largeTitle.weight(.bold))
            Text(L10n.string("ios.welcome.subtitle"))
                .font(.callout)
                .foregroundStyle(IOSTheme.dim)
        }
    }

    private func point(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: IOSTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(IOSTheme.amber)
                // A fixed column, so four different glyphs do not produce four
                // different left edges for the text beside them.
                .frame(width: 32, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: IOSTheme.Spacing.hair) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(IOSTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
