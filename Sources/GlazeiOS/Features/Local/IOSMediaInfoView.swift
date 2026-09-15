import GlazeCore
import SwiftUI

/// What this film claims to be, and a way to correct it.
///
/// Reached by holding a film in the list. Two things happen here and they are kept
/// apart on purpose: reading what is currently recorded, and replacing it. Nothing is
/// written until a specific film is chosen from the results and confirmed.
struct IOSMediaInfoView: View {
    let item: MediaLibraryItem

    @Environment(\.dismiss) private var dismiss
    @Environment(IOSUserPreferences.self) private var preferences
    @State private var model: IOSMetadataModel
    @State private var query: String
    /// A film the viewer picked, held until they confirm. The write replaces files on
    /// disk, so it does not happen on a tap in a list.
    @State private var pending: MediaMetadataMatch?
    /// Set once the sidecars are rewritten, so the list behind can reload.
    var onChanged: () -> Void = {}

    init(item: MediaLibraryItem, onChanged: @escaping () -> Void = {}) {
        self.item = item
        self.onChanged = onChanged
        _model = State(initialValue: IOSMetadataModel(item: item, videoURL: item.playbackURL))
        _query = State(initialValue: item.parsed.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                currentSection
                lookUpSection

                switch model.stage {
                case .results(let ranked): results(ranked)
                case .failed(let text): note(text, symbol: "exclamationmark.triangle")
                case .done(let text): note(text, symbol: "checkmark.circle")
                case .idle, .searching, .applying: EmptyView()
                }
            }
            .glazeListBackground()
            .navigationTitle(L10n.string("ios.metadata.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.close")) { dismiss() }
                }
            }
            .alert(
                L10n.string("ios.metadata.confirm.title"),
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                presenting: pending
            ) { match in
                Button(L10n.string("common.cancel"), role: .cancel) { pending = nil }
                Button(L10n.string("ios.metadata.confirm.apply")) {
                    let chosen = match
                    pending = nil
                    Task {
                        await model.apply(chosen)
                        onChanged()
                    }
                }
            } message: { match in
                Text(
                    String(
                        format: L10n.string("ios.metadata.confirm.detail"),
                        match.title,
                        match.year.map(String.init) ?? "—",
                        item.playbackURL.deletingPathExtension().lastPathComponent
                    )
                )
            }
        }
    }

    // MARK: - What is recorded now

    private var currentSection: some View {
        Section {
            LabeledContent(L10n.string("ios.metadata.field.title"), value: item.displayTitle)
            if let year = item.year {
                LabeledContent(L10n.string("ios.metadata.field.year"), value: String(year))
            }
            LabeledContent(L10n.string("ios.metadata.field.file")) {
                Text(item.playbackURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(IOSTheme.dim)
                    .multilineTextAlignment(.trailing)
            }
            if let plot = item.plot, !plot.isEmpty {
                Text(plot)
                    .font(.caption)
                    .foregroundStyle(IOSTheme.dim)
            }
        } header: {
            Text(L10n.string("ios.metadata.current"))
        } footer: {
            // Says where the claim comes from, because that is what tells someone
            // whether it is worth correcting.
            Text(L10n.string(item.metadata == nil ? "ios.metadata.from_name" : "ios.metadata.from_nfo"))
        }
    }

    // MARK: - Looking it up again

    @ViewBuilder
    private var lookUpSection: some View {
        Section {
            TextField(L10n.string("ios.metadata.field.search"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(look)

            if model.stage == .searching || model.stage == .applying {
                HStack(spacing: IOSTheme.Spacing.small) {
                    ProgressView()
                    Text(L10n.string(model.stage == .applying ? "ios.metadata.writing" : "ios.metadata.searching"))
                        .foregroundStyle(IOSTheme.dim)
                }
            } else {
                Button(L10n.string("ios.metadata.look_up"), action: look)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(L10n.string("ios.metadata.look_up"))
        } footer: {
            Text(L10n.string(hasKey ? "ios.metadata.footer" : "ios.metadata.no_key"))
        }
    }

    private func results(_ ranked: [RankedMetadataMatch]) -> some View {
        Section(L10n.string("ios.metadata.results")) {
            if ranked.isEmpty {
                Text(L10n.string("ios.metadata.not_found"))
                    .foregroundStyle(IOSTheme.dim)
            }
            ForEach(ranked) { candidate in
                Button { pending = candidate.match } label: { row(candidate) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func row(_ candidate: RankedMetadataMatch) -> some View {
        HStack(alignment: .top, spacing: IOSTheme.Spacing.medium) {
            poster(candidate.match.posterURL)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.match.title)
                    .font(.body)
                HStack(spacing: IOSTheme.Spacing.small) {
                    if let year = candidate.match.year {
                        Text(String(year))
                    }
                    // The name it was released under, when that is not the name shown.
                    // It is usually the half of the filename someone recognises.
                    if let original = candidate.match.originalTitle,
                       original != candidate.match.title {
                        Text(original).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(IOSTheme.dim)

                if let overview = candidate.match.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(IOSTheme.dim)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func poster(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(IOSTheme.dim.opacity(0.2))
        }
        .frame(width: 46, height: 69)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func note(_ text: String, symbol: String) -> some View {
        Section {
            Label(text, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(IOSTheme.dim)
        }
    }

    private var hasKey: Bool {
        !preferences.tmdbAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func look() {
        Task {
            await model.search(
                query,
                // Only when the viewer has not changed the title: a year taken from the
                // old, wrong record would narrow the search to the same wrong answer.
                year: query == item.parsed.title ? item.year : nil,
                apiKey: preferences.tmdbAPIKey,
                languageCode: Locale.preferredLanguages.first ?? "en"
            )
        }
    }
}
