import GlazeCore
import SwiftUI

/// What sits in one folder on the device.
struct IOSLocalEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A folder, and what is anywhere below it.
        case folder(films: Int, books: Int)
        case film(MediaLibraryItem)
    }

    let url: URL
    let kind: Kind

    var id: String { url.standardizedFileURL.absoluteString }
    var name: String { url.lastPathComponent }
}

/// The Glaze folder, exactly as it is.
///
/// This replaced a poster grid whose identity changed with whichever source was
/// selected somewhere else — a screen that could not tell you what you were looking
/// at, and whose title was the name of a server you had to remember choosing.
///
/// Films on a phone arrive as folders someone made: the film, its subtitle and its
/// `.nfo` together. Showing the folder as it is means what you put in is what you
/// see, and there is no hidden state to keep in your head.
struct IOSLocalBrowserView: View {
    let folder: URL
    var isRoot = false

    @Environment(IOSUserPreferences.self) private var preferences
    @State private var entries: [IOSLocalEntry] = []
    @State private var playing: IOSLocalEntry?
    /// The film whose record is being read or corrected. Held apart from `playing` so
    /// that opening the information never starts the film.
    @State private var inspecting: MediaLibraryItem?
    /// Bumped when the player closes, so NEW badges and watched marks reflect what was
    /// just watched. The store is read at render time and nothing else would redraw.
    @State private var watchRevision = 0

    private let positions = PlaybackPositionStore()

    var body: some View {
        List {
            if entries.isEmpty {
                Section { empty }
            }
            ForEach(entries) { entry in
                row(entry)
            }
        }
        .glazeListBackground()
        .navigationTitle(isRoot ? L10n.string("ios.local.title") : folder.lastPathComponent)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .onAppear { reload() }
        .refreshable { reload() }
        .sheet(item: $inspecting) { item in
            IOSMediaInfoView(item: item, onChanged: reload)
                .environment(preferences)
        }
        .fullScreenCover(item: $playing, onDismiss: {
            IOSScreenOrientation.release()
            watchRevision += 1
        }) { entry in
            if case .film(let item) = entry.kind {
                let resource = IOSLocalFolder.resource(for: item)
                IOSPlayerView(
                    resource: resource,
                    title: item.listTitle,
                    startAt: positions.position(for: .network(resource)) ?? 0,
                    subtitleURL: preferredSubtitle(for: item),
                    queue: queue(startingWith: item)
                )
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: IOSLocalEntry) -> some View {
        switch entry.kind {
        case .folder(let films, let books):
            NavigationLink {
                IOSLocalBrowserView(folder: entry.url)
            } label: {
                IOSListRow(symbol: "folder", title: entry.name, detail: detail(films: films, books: books))
            }
        case .film(let item):
            let resource = MediaResource.network(IOSLocalFolder.resource(for: item))
            let watch = positions.state(for: resource)
            Button { playing = entry } label: {
                IOSListRow(symbol: "film", title: item.listTitle, detail: detail(for: item), watch: watch)
                    // Re-reads the store after the player closes.
                    .id("\(entry.id)#\(watchRevision)")
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    inspecting = item
                } label: {
                    Label(L10n.string("ios.metadata.title"), systemImage: "info.circle")
                }
                watchToggle(resource, isWatched: watch == .watched)
            }
        }
    }

    /// Every film in this folder, in the order the list shows them — which is the order
    /// someone numbered the files, so episode two follows episode one.
    private func queue(startingWith item: MediaLibraryItem) -> PlaybackQueue {
        let films = entries.compactMap { entry -> PlaybackQueueItem? in
            guard case .film(let film) = entry.kind else { return nil }
            return PlaybackQueueItem(resource: IOSLocalFolder.resource(for: film), title: film.listTitle)
        }
        let current = PlaybackQueueItem(resource: IOSLocalFolder.resource(for: item), title: item.listTitle)
        return PlaybackQueue(items: films, current: current)
    }

    /// For a film watched somewhere else, or one that should read as new again.
    @ViewBuilder
    private func watchToggle(_ resource: MediaResource, isWatched: Bool) -> some View {
        Button {
            if isWatched { positions.markUnwatched(resource) } else { positions.markWatched(resource) }
            watchRevision += 1
        } label: {
            Label(
                L10n.string(isWatched ? "ios.watch.mark_unwatched" : "ios.watch.mark_watched"),
                systemImage: isWatched ? "circle" : "checkmark.circle"
            )
        }
    }

    /// A folder says what is under it in the order it is likely to matter: films
    /// first, because this is the film browser, then books so the shelf's own folder
    /// does not read as an empty one.
    private func detail(films: Int, books: Int) -> String {
        var parts: [String] = []
        if films > 0 {
            parts.append(String(format: L10n.string("ios.local.film_count_format"), films))
        }
        if books > 0 {
            parts.append(String(format: L10n.string("ios.local.book_count_format"), books))
        }
        return parts.isEmpty ? L10n.string("ios.local.folder") : parts.joined(separator: " · ")
    }

    /// The subtitle in the viewer's language when the folder has one, so a film with
    /// `film.ko.srt` beside it opens already subtitled.
    private func preferredSubtitle(for item: MediaLibraryItem) -> URL? {
        guard preferences.automaticallySelectSubtitles else { return nil }
        let wanted = preferences.defaultSubtitleLanguageCode
        return item.subtitleURLs.first { SubtitleFile.manual(url: $0).languageCode == wanted }
            ?? item.subtitleURLs.first
    }

    private func detail(for item: MediaLibraryItem) -> String {
        var parts: [String] = []
        if let bytes = item.byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        if !item.subtitleURLs.isEmpty {
            parts.append(
                String(format: L10n.string("ios.device.subtitle_count_format"), item.subtitleURLs.count)
            )
        }
        return parts.joined(separator: " · ")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.small) {
            Image(systemName: "film.stack")
                .font(.largeTitle)
                .foregroundStyle(IOSTheme.dim)
            Text(L10n.string("ios.local.empty"))
                .font(.callout)
                .foregroundStyle(IOSTheme.dim)
        }
        .padding(.vertical, IOSTheme.Spacing.medium)
    }

    private func reload() {
        entries = IOSLocalFolder.read(folder)
    }
}
