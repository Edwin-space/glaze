import GlazeCore
import SwiftUI

/// Asked when a film opens carrying subtitles, but none in the language the viewer
/// reads — and one of the tracks it does carry can be translated.
///
/// The question is really about waiting. Translating a feature film takes minutes, so
/// the two answers that matter are "start it now and let the lines catch up" and
/// "translate it first, I will wait". Deciding either way for someone would be wrong,
/// so it is asked once and the answer is remembered.
struct AutoTranslationPrompt: View {
    let sourceName: String
    let sourceLanguageOrigin: SubtitleLanguageAssessment.Origin
    @Binding var sourceLanguageCode: String
    let targetLanguageName: String
    let onChoose: (SubtitleTranslationTiming) -> Void
    let onDecline: () -> Void

    @State private var remembers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: L10n.string("subtitle.auto_translate.title"), targetLanguageName))
                    .font(.title2.weight(.semibold))
                Text(
                    String(
                        format: L10n.string("subtitle.auto_translate.detail"),
                        L10n.languageName(for: sourceLanguageCode) ?? L10n.string("subtitle.language.unknown"),
                        targetLanguageName
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("subtitle.auto_translate.loaded"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(sourceName)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .help(sourceName)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("subtitle.auto_translate.source_name")
                Picker(L10n.string("subtitle.language.source"), selection: $sourceLanguageCode) {
                    Text(L10n.string("subtitle.language.unknown")).tag("")
                    ForEach(languageCodes, id: \.self) { code in
                        Text(L10n.languageName(for: code) ?? code).tag(code)
                    }
                }
                .accessibilityIdentifier("subtitle.auto_translate.source_language")
                Text(L10n.string(languageHintKey))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 10) {
                choice(
                    timing: .whileWatching,
                    titleKey: "subtitle.auto_translate.while_watching",
                    detailKey: "subtitle.auto_translate.while_watching.detail",
                    systemImage: "play.circle",
                    isProminent: true
                )
                choice(
                    timing: .beforeWatching,
                    titleKey: "subtitle.auto_translate.before_watching",
                    detailKey: "subtitle.auto_translate.before_watching.detail",
                    systemImage: "clock.arrow.circlepath",
                    isProminent: false
                )
            }

            Toggle(L10n.string("subtitle.auto_translate.remember"), isOn: $remembers)
                .toggleStyle(.checkbox)
                .font(.callout)

            Text(L10n.string("subtitle.auto_translate.preserves_original"))
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L10n.string("subtitle.auto_translate.keep_original")) {
                    if remembers { GlazePreferences.shared.autoTranslation = .off }
                    onDecline()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("subtitle.auto_translate.decline")
            }
        }
        .padding(24)
        .frame(width: 500)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subtitle.auto_translate.prompt")
        .preferredColorScheme(.dark)
    }

    private var languageCodes: [String] {
        var codes = ["ko", "en", "ja", "zh", "es", "fr", "de", "pt", "it", "ru", "ar", "hi", "id", "th", "tr", "vi"]
        if !sourceLanguageCode.isEmpty, !codes.contains(sourceLanguageCode) { codes.append(sourceLanguageCode) }
        return codes
    }

    private var languageHintKey: String {
        switch sourceLanguageOrigin {
        case .content: "subtitle.auto_translate.detected"
        case .metadata: "subtitle.auto_translate.check_language"
        case .user: "subtitle.auto_translate.user_language"
        case .unknown: "subtitle.auto_translate.unknown_language"
        }
    }

    private func choice(
        timing: SubtitleTranslationTiming,
        titleKey: String,
        detailKey: String,
        systemImage: String,
        isProminent: Bool
    ) -> some View {
        Button {
            if remembers {
                GlazePreferences.shared.autoTranslation =
                    timing == .whileWatching ? .whileWatching : .beforeWatching
            }
            onChoose(timing)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string(titleKey)).font(.headline)
                    Text(L10n.string(detailKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("subtitle.auto_translate.\(timing.rawValue)")
        .tint(isProminent ? .accentColor : nil)
    }
}
