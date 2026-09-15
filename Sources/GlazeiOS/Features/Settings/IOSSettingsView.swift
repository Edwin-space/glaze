import GlazeBooks
import GlazeCore
import SwiftUI

/// The app's own settings, rather than settings that only exist mid-film.
///
/// Everything here used to live in a sheet inside the player, which meant the only
/// way to change your default subtitle language was to start playing something first.
struct IOSSettingsView: View {
    let library: IOSLibraryModel
    let books: IOSBookLibraryModel
    let onOpenDevice: () -> Void

    @Environment(IOSUserPreferences.self) private var preferences
    @State private var files = IOSDeviceFilesModel()
    @State private var cache = IOSCacheStore()
    @State private var isClearingCache = false

    private let sizeOptions: [(key: String, value: Float)] = [
        ("subtitle.appearance.size.small", 85),
        ("subtitle.appearance.size.medium", 100),
        ("subtitle.appearance.size.large", 125),
        ("subtitle.appearance.size.extra_large", 150)
    ]

    var body: some View {
        @Bindable var preferences = preferences

        List {
            Section {
                Picker(L10n.string("tv.settings.default_subtitle_language"), selection: $preferences.defaultSubtitleLanguageCode) {
                    ForEach(IOSSubtitleLanguage.supported) { language in
                        Text(language.localizedName).tag(language.id)
                    }
                }
                Picker(L10n.string("subtitle.appearance.size"), selection: $preferences.subtitleScale) {
                    ForEach(sizeOptions, id: \.value) { option in
                        Text(L10n.string(option.key)).tag(option.value)
                    }
                }
                Toggle(L10n.string("tv.settings.auto_select_subtitles"), isOn: $preferences.automaticallySelectSubtitles)
            } header: {
                Text(L10n.string("ios.settings.subtitles"))
            } footer: {
                Text(L10n.string("ios.settings.subtitles.detail"))
            }

            Section {
                Picker(L10n.string("ios.player.rate"), selection: $preferences.playbackRate) {
                    ForEach(IOSPlaybackModel.rateOptions, id: \.self) { rate in
                        Text(Self.rateLabel(rate)).tag(rate)
                    }
                }
            } header: {
                Text(L10n.string("ios.settings.playback"))
            } footer: {
                Text(L10n.string("ios.settings.playback.detail"))
            }

            Section {
                Picker(L10n.string("book.reader.direction"), selection: $preferences.readingDirection) {
                    ForEach(ReadingDirection.allCases, id: \.self) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                Toggle(L10n.string("book.reader.double"), isOn: $preferences.doublePageSpreads)
                Picker(L10n.string("book.reader.theme"), selection: $preferences.readingTheme) {
                    ForEach(ReadingTheme.allCases, id: \.self) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                LabeledContent(L10n.string("ios.settings.text_size")) {
                    Text(String(format: "%.0f%%", preferences.readingFontScale * 100))
                        .monospacedDigit()
                }
            } header: {
                Text(L10n.string("ios.settings.reading"))
            } footer: {
                Text(L10n.string("ios.settings.reading.detail"))
            }

            Section {
                Button(action: onOpenDevice) {
                    LabeledContent(L10n.string("ios.device.title")) {
                        Text(
                            String(
                                format: L10n.string("ios.device.summary_format"),
                                files.videos.count,
                                ByteCountFormatter.string(fromByteCount: files.totalByteCount, countStyle: .file)
                            )
                        )
                    }
                }
                if !books.library.isEmpty {
                    LabeledContent(L10n.string("book.shelf.title")) {
                        Text(
                            String(
                                format: L10n.string("book.shelf.count_format"),
                                books.library.allBooks.count
                            )
                        )
                    }
                }
            } header: {
                Text(L10n.string("ios.sources.device"))
            }

            Section {
                LabeledContent(L10n.string("ios.settings.cache.size")) {
                    if cache.isMeasuring {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(ByteCountFormatter.string(fromByteCount: cache.byteCount, countStyle: .file))
                    }
                }
                Button(L10n.string("ios.settings.cache.clear"), role: .destructive) {
                    isClearingCache = true
                }
                .disabled(cache.byteCount == 0)
            } header: {
                Text(L10n.string("ios.settings.cache"))
            } footer: {
                Text(L10n.string("ios.settings.cache.detail"))
            }

            Section {
                SecureField(L10n.string("ios.settings.tmdb_key"), text: $preferences.tmdbAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let url = URL(string: "https://www.themoviedb.org/settings/api") {
                    Link(L10n.string("ios.settings.tmdb_get"), destination: url)
                }
            } header: {
                Text(L10n.string("ios.settings.metadata"))
            } footer: {
                Text(L10n.string("ios.settings.metadata.detail"))
            }

            Section(L10n.string("ios.settings.about")) {
                LabeledContent(L10n.string("ios.settings.version"), value: Self.version)
                NavigationLink(L10n.string("legal.title")) {
                    IOSLicensesView()
                }
                Link(destination: Self.privacyPolicyURL) {
                    LabeledContent(L10n.string("ios.settings.privacy")) {
                        Image(systemName: "arrow.up.right")
                    }
                }
            }
        }
        .glazeListBackground()
        .navigationTitle(L10n.string("settings.title"))
        .task { cache.refresh() }
        .confirmationDialog(
            L10n.string("ios.settings.cache.clear"),
            isPresented: $isClearingCache,
            titleVisibility: .visible
        ) {
            Button(L10n.string("ios.settings.cache.clear"), role: .destructive) { cache.clear() }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("ios.settings.cache.confirm"))
        }
        .onAppear {
            files.reload()
            if books.phase == .idle { books.reload() }
        }
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private static let privacyPolicyURL = URL(
        string: "https://edwin-space.github.io/glaze/privacy/"
    )!

    private static func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? String(format: "%.0f×", rate) : String(format: "%.2g×", rate)
    }
}
