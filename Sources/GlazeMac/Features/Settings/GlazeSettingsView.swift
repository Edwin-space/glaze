import GlazeCore
import SwiftUI

/// The app's Settings window.
///
/// These choices used to be reachable only from the subtitle inspector, which needs a
/// video open — there was no way to pick a transcription model, or decide where
/// subtitles are saved, before opening anything. The inspector keeps them too, where
/// they are in reach while working on a file; both edit `GlazePreferences`.
struct GlazeSettingsView: View {
    @State private var preferences = GlazePreferences.shared

    var body: some View {
        TabView {
            subtitleSettings
                .tabItem { Label(L10n.string("settings.tab.subtitles"), systemImage: "captions.bubble") }

            translationSettings
                .tabItem { Label(L10n.string("settings.tab.translation"), systemImage: "character.bubble") }

            appearanceSettings
                .tabItem { Label(L10n.string("settings.tab.appearance"), systemImage: "textformat.size") }

            metadataSettings
                .tabItem { Label(L10n.string("settings.tab.metadata"), systemImage: "film") }
        }
        .frame(width: 480)
    }

    private var subtitleSettings: some View {
        Form {
            Section {
                Picker(selection: $preferences.transcriptionTier) {
                    ForEach(TranscriptionModelTier.allCases, id: \.self) { tier in
                        Text(L10n.string(tier.labelKey)).tag(tier)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.model.tier", help: "help.subtitle.model_tier")
                }

                Text(
                    String(
                        format: L10n.string("subtitle.model.download_format"),
                        preferences.transcriptionTier.approximateDownloadMegabytes
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(L10n.string("settings.section.generation"))
            }

            Section {
                Picker(selection: $preferences.storageLocation) {
                    ForEach(SubtitleStorageLocation.allCases, id: \.self) { location in
                        Text(L10n.string(location.labelKey)).tag(location)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.panel.storage", help: "help.subtitle.storage")
                }
            } header: {
                Text(L10n.string("settings.section.storage"))
            }
        }
        .formStyle(.grouped)
    }

    /// How subtitles are drawn. Watching on a laptop and watching across a room are
    /// not the same, and neither is a film whose burned-in signage sits exactly where
    /// a subtitle lands.
    private var appearanceSettings: some View {
        Form {
            Section {
                Picker(selection: $preferences.textSize) {
                    ForEach(SubtitleTextSize.allCases, id: \.self) { size in
                        Text(L10n.string(size.labelKey)).tag(size)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.appearance.size", help: "help.subtitle.size")
                }

                Picker(selection: $preferences.position) {
                    ForEach(SubtitlePosition.allCases, id: \.self) { position in
                        Text(L10n.string(position.labelKey)).tag(position)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.appearance.position", help: "help.subtitle.position")
                }

                Picker(selection: $preferences.background) {
                    ForEach(SubtitleBackground.allCases, id: \.self) { background in
                        Text(L10n.string(background.labelKey)).tag(background)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.appearance.background", help: "help.subtitle.background")
                }
            } header: {
                Text(L10n.string("settings.section.appearance"))
            }
        }
        .formStyle(.grouped)
    }

    /// Where the viewer's own TMDB key goes.
    private var metadataSettings: some View {
        Form {
            Section {
                LabeledContent {
                    TextField("", text: $preferences.tmdbAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                } label: {
                    GlazeHelpLabel("metadata.settings.key", help: "help.metadata.key")
                }

                Link(
                    L10n.string("metadata.attribution"),
                    destination: URL(string: "https://www.themoviedb.org")!
                )
                .font(.caption)
            } header: {
                Text(L10n.string("settings.section.metadata"))
            }
        }
        .formStyle(.grouped)
    }

    private var translationSettings: some View {
        Form {
            Section {
                Picker(selection: $preferences.translationEngineID) {
                    Text(L10n.string(SubtitleTranslationEngineID.appleTranslation.labelKey))
                        .tag(SubtitleTranslationEngineID.appleTranslation)
                    Text(L10n.string(SubtitleTranslationEngineID.appleFoundationModel.labelKey))
                        .tag(SubtitleTranslationEngineID.appleFoundationModel)
                } label: {
                    GlazeHelpLabel("subtitle.translate.engine", help: "help.subtitle.translate_engine")
                }

                if preferences.translationEngineID == .appleFoundationModel {
                    Text(L10n.string("subtitle.translate.engine.on_device_ai_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(selection: $preferences.translationQuality) {
                        ForEach(SubtitleTranslationQuality.allCases, id: \.self) { quality in
                            Text(L10n.string(quality.labelKey)).tag(quality)
                        }
                    } label: {
                        GlazeHelpLabel("subtitle.translate.quality", help: "help.subtitle.translate_quality")
                    }
                }

                Picker(selection: $preferences.translationOutput) {
                    ForEach(SubtitleTranslationOutput.allCases, id: \.self) { output in
                        Text(L10n.string(output.labelKey)).tag(output)
                    }
                } label: {
                    GlazeHelpLabel("subtitle.translate.output", help: "help.subtitle.translate_output")
                }
            } header: {
                Text(L10n.string("settings.section.translation"))
            }
        }
        .formStyle(.grouped)
    }
}
