import GlazeCore
import SwiftUI
import UniformTypeIdentifiers

/// Subtitles and audio, while the film keeps playing behind the sheet.
struct IOSPlayerSettingsView: View {
    let model: IOSPlaybackModel
    var subtitleCandidates: (@Sendable () async -> [IOSSubtitleCandidate])?

    @Environment(\.dismiss) private var dismiss
    @Environment(IOSUserPreferences.self) private var preferences
    @State private var candidates: [IOSSubtitleCandidate] = []
    @State private var isLookingForFiles = false
    @State private var isImporting = false
    @State private var importFailure: String?

    private let sizeOptions: [(key: String, value: Float)] = [
        ("subtitle.appearance.size.small", 85),
        ("subtitle.appearance.size.medium", 100),
        ("subtitle.appearance.size.large", 125),
        ("subtitle.appearance.size.extra_large", 150)
    ]

    var body: some View {
        NavigationStack {
            Form {
                subtitleTrackSection
                subtitleFileSection
                subtitleAdjustmentSection
                audioSection
                defaultsSection
            }
            .navigationTitle(L10n.string("ios.player.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.close")) { dismiss() }
                }
            }
            .task { await loadCandidates() }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: Self.importableTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert(
                L10n.string("ios.player.subtitle.import_failed"),
                isPresented: Binding(get: { importFailure != nil }, set: { if !$0 { importFailure = nil } })
            ) {
                Button(L10n.string("common.close"), role: .cancel) { importFailure = nil }
            } message: {
                Text(importFailure ?? "")
            }
        }
    }

    // MARK: - Sections

    private var subtitleTrackSection: some View {
        Section(L10n.string("ios.player.subtitle.tracks")) {
            if model.subtitleTracks.isEmpty {
                Text(L10n.string("ios.player.subtitle.none"))
                    .foregroundStyle(IOSTheme.dim)
            }
            ForEach(model.subtitleTracks) { track in
                Button { model.selectSubtitleTrack(id: track.id) } label: {
                    row(track.title, isSelected: track.isSelected)
                }
            }
            Button { model.disableSubtitles() } label: {
                row(
                    L10n.string("ios.player.subtitle.off"),
                    isSelected: !model.subtitleTracks.contains(where: \.isSelected)
                )
            }
        }
    }

    /// The film is `Parasite.2019.1080p.mkv` and the subtitle someone downloaded is
    /// `기생충.srt`. Nothing can match those by name, so the folder is simply shown.
    private var subtitleFileSection: some View {
        Section {
            if isLookingForFiles {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.string("ios.player.subtitle.searching")).foregroundStyle(IOSTheme.dim)
                }
            }
            ForEach(candidates) { candidate in
                Button {
                    model.addSubtitle(candidate.url)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name).lineLimit(1)
                            if candidate.isBesideTheFilm {
                                Text(L10n.string("ios.player.subtitle.matched"))
                                    .font(.caption2)
                                    .foregroundStyle(IOSTheme.dim)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.down.circle").foregroundStyle(IOSTheme.amber)
                    }
                }
            }
            Button {
                isImporting = true
            } label: {
                Label(L10n.string("ios.player.subtitle.import"), systemImage: "folder")
            }
        } header: {
            Text(L10n.string("ios.player.subtitle.files"))
        } footer: {
            Text(L10n.string("ios.player.subtitle.files.hint"))
        }
    }

    private var subtitleAdjustmentSection: some View {
        Section(L10n.string("ios.player.subtitle.adjust")) {
            HStack {
                Text(L10n.string("ios.player.subtitle.delay"))
                Spacer()
                Button { model.adjustSubtitleDelay(by: -0.5) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                Text(String(format: "%.1fs", model.subtitleDelay))
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: 52)
                Button { model.adjustSubtitleDelay(by: 0.5) } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            Picker(L10n.string("subtitle.appearance.size"), selection: Binding(
                get: { model.subtitleScale },
                set: { newValue in
                    model.setSubtitleScale(newValue)
                    preferences.subtitleScale = newValue
                }
            )) {
                ForEach(sizeOptions, id: \.value) { option in
                    Text(L10n.string(option.key)).tag(option.value)
                }
            }
        }
    }

    private var audioSection: some View {
        Section(L10n.string("ios.player.audio")) {
            if model.audioTracks.isEmpty {
                Text(L10n.string("ios.player.audio.none")).foregroundStyle(IOSTheme.dim)
            }
            ForEach(model.audioTracks) { track in
                Button { model.selectAudioTrack(id: track.id) } label: {
                    row(track.title, isSelected: track.isSelected)
                }
            }
        }
    }

    private var defaultsSection: some View {
        @Bindable var preferences = preferences
        return Section(L10n.string("ios.player.defaults")) {
            Picker(L10n.string("tv.settings.default_subtitle_language"), selection: $preferences.defaultSubtitleLanguageCode) {
                ForEach(IOSSubtitleLanguage.supported) { language in
                    Text(language.localizedName).tag(language.id)
                }
            }
            Toggle(
                L10n.string("tv.settings.auto_select_subtitles"),
                isOn: $preferences.automaticallySelectSubtitles
            )
        }
    }

    private func row(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(IOSTheme.amber)
            }
        }
    }

    // MARK: - Files

    private static let importableTypes: [UTType] = {
        let named = ["srt", "vtt", "smi", "ass", "ssa", "sub"].compactMap {
            UTType(filenameExtension: $0)
        }
        // Some of those extensions have no declared type on iOS, so plain data has to
        // stay in the list or the picker would refuse the file.
        return named + [.plainText, .data]
    }()

    private func loadCandidates() async {
        guard let subtitleCandidates, candidates.isEmpty else { return }
        isLookingForFiles = true
        candidates = await subtitleCandidates()
        isLookingForFiles = false
    }

    /// The picked file lives outside the sandbox, and VLC reads it later on its own
    /// thread — long after the security-scoped access would have been given up. Copying
    /// it in is the only form that survives.
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let picked = urls.first else {
            if case .failure(let error) = result { importFailure = error.localizedDescription }
            return
        }

        let accessed = picked.startAccessingSecurityScopedResource()
        defer { if accessed { picked.stopAccessingSecurityScopedResource() } }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(picked.lastPathComponent)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: picked, to: destination)
            model.addSubtitle(destination)
            dismiss()
        } catch {
            importFailure = error.localizedDescription
        }
    }
}
