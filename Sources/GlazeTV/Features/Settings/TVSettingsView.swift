import GlazeCore
import SwiftUI

struct TVSettingsView: View {
    @Bindable var preferences: TVUserPreferences
    var onOpenPairing: () -> Void = {}

    @State private var showsLicenses = false

    private let sizeOptions: [(String, Float)] = [
        ("subtitle.appearance.size.small", 85),
        ("subtitle.appearance.size.medium", 100),
        ("subtitle.appearance.size.large", 125),
        ("subtitle.appearance.size.extra_large", 150)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 46) {
                header
                languageSection
                appearanceSection
                playbackSection
                aboutSection
            }
            .padding(.horizontal, 84)
            .padding(.top, 70)
            .padding(.bottom, 90)
        }
        .background(TVTheme.ground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("settings.title"))
                .font(.system(size: 58, weight: .bold))
            Text(L10n.string("tv.settings.detail"))
                .font(.system(size: 25))
                .foregroundStyle(TVTheme.dim)
        }
    }

    private var languageSection: some View {
        settingsSection(title: L10n.string("subtitle.language.section")) {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.string("tv.settings.default_subtitle_language"))
                            .font(.system(size: 28, weight: .semibold))
                        Text(L10n.string("tv.settings.default_subtitle_language.detail"))
                            .font(.system(size: 21))
                            .foregroundStyle(TVTheme.dim)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(TVSubtitleLanguage.supported) { language in
                                Button {
                                    preferences.defaultSubtitleLanguageCode = language.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(language.localizedName)
                                            .lineLimit(1)
                                        if preferences.defaultSubtitleLanguageCode == language.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(TVTheme.amber)
                                        }
                                    }
                                    .font(.system(size: 23, weight: .medium))
                                    .frame(minWidth: 180, minHeight: 62)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 14)
                    }
                    .focusSection()
                }
                .padding(26)

                Divider().overlay(.white.opacity(0.12))

                Toggle(isOn: $preferences.automaticallySelectSubtitles) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.string("tv.settings.auto_select_subtitles"))
                            .font(.system(size: 28, weight: .semibold))
                        Text(L10n.string("tv.settings.auto_select_subtitles.detail"))
                            .font(.system(size: 21))
                            .foregroundStyle(TVTheme.dim)
                    }
                }
                .padding(26)
            }
        }
    }

    private var appearanceSection: some View {
        settingsSection(title: L10n.string("settings.section.appearance")) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.string("subtitle.appearance.size"))
                    .font(.system(size: 27, weight: .semibold))

                HStack(spacing: 16) {
                    ForEach(sizeOptions, id: \.0) { option in
                        Button {
                            preferences.subtitleScale = option.1
                        } label: {
                            HStack(spacing: 10) {
                                Text(L10n.string(option.0))
                                if abs(preferences.subtitleScale - option.1) < 1 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(TVTheme.amber)
                                }
                            }
                            .font(.system(size: 24, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text(L10n.string("tv.settings.appearance.preview"))
                    .font(.system(size: CGFloat(preferences.subtitleScale * 0.34), weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(26)
        }
    }

    private var playbackSection: some View {
        settingsSection(title: L10n.string("tv.settings.playback")) {
            HStack(spacing: 22) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 36))
                    .foregroundStyle(TVTheme.amber)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("tv.settings.seek_interval"))
                        .font(.system(size: 28, weight: .semibold))
                    Text(L10n.string("tv.settings.seek_interval.detail"))
                        .font(.system(size: 21))
                        .foregroundStyle(TVTheme.dim)
                }
                Spacer()
                Text("10 " + L10n.string("tv.settings.seconds"))
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(26)
        }
    }

    private var aboutSection: some View {
        settingsSection(title: L10n.string("tv.settings.setup")) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("tv.settings.setup_again"))
                        .font(.system(size: 28, weight: .semibold))
                    Text(L10n.string("tv.settings.setup_again.detail"))
                        .font(.system(size: 21))
                        .foregroundStyle(TVTheme.dim)
                }
                Spacer()
                Button(L10n.string("tv.settings.start")) {
                    preferences.restartOnboarding()
                }
            }
            .padding(26)

            // Typing a NAS address and password on a remote control is the worst job
            // in the app. The phone has already done it.
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("tv.pairing.open"))
                        .font(.system(size: 28, weight: .semibold))
                    Text(L10n.string("tv.pairing.detail"))
                        .font(.system(size: 21))
                        .foregroundStyle(TVTheme.dim)
                        .frame(maxWidth: 900, alignment: .leading)
                }
                Spacer()
                Button(L10n.string("tv.settings.start")) { onOpenPairing() }
            }
            .padding(26)

            // Not a nicety: libVLC is LGPL and the licence requires that whoever has a
            // copy of this app can read the notice and find the source.
            HStack {
                Text(L10n.string("legal.title"))
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Button(L10n.string("legal.view")) { showsLicenses = true }
            }
            .padding(26)
        }
        .fullScreenCover(isPresented: $showsLicenses) {
            TVLicensesView()
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 31, weight: .semibold))
            content()
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
