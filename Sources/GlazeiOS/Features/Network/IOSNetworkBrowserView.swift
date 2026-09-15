import GlazeCore
import SwiftUI

/// Where to go next inside a server. Only a path, so the navigation stack stays
/// cheap and the connection lives in one place.
struct IOSNetworkFolderRef: Hashable {
    let path: String
    let name: String
}

/// A folder on a server, exactly as the server reports it.
///
/// Replaces the poster grid, which was the wrong shape for a NAS: it demanded that the
/// whole tree be read before it could show anything, and most of what came back had no
/// artwork, so it was a grid of grey rectangles produced at great cost. A folder people
/// made is already organised; showing it as it is costs one request and tells the truth.
struct IOSNetworkBrowserView: View {
    let browser: IOSNetworkBrowser
    let folder: IOSNetworkFolderRef
    var isRoot = false

    @Environment(IOSUserPreferences.self) private var preferences
    @State private var entries: [IOSNetworkEntry] = []
    @State private var phase: Phase = .loading
    @State private var playing: IOSNetworkEntry?
    /// Bumped when the player closes so NEW and watched marks catch up.
    @State private var watchRevision = 0

    private let positions = PlaybackPositionStore()

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        @Bindable var preferences = preferences

        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large)
            case .failed(let message):
                failure(message)
            case .ready:
                if preferences.browseLayout == .list {
                    list
                } else {
                    tiles(preferences.browseLayout)
                }
            }
        }
        .glazeListBackground()
        .navigationTitle(isRoot ? browser.serverName : folder.name)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IOSBrowseLayoutMenu(layout: $preferences.browseLayout)
            }
        }
        // Read once when the folder is opened. Coming back to a folder already read
        // does not go to the server again — the old library re-read everything on
        // every appearance, which is what made the app feel like it was thinking.
        .task(id: folder.path) { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $playing, onDismiss: {
            IOSScreenOrientation.release()
            watchRevision += 1
        }) { entry in
            if case .film(let resource, let parsed) = entry.kind {
                IOSPlayerView(
                    resource: resource,
                    title: parsed.listTitle,
                    startAt: positions.position(for: .network(resource)) ?? 0,
                    subtitleURL: preferredSubtitle(for: resource),
                    queue: queue(startingWith: resource, title: parsed.listTitle)
                )
            }
        }
    }

    // MARK: - Layouts

    private var list: some View {
        List {
            if entries.isEmpty { Section { empty } }
            ForEach(entries) { entry in
                switch entry.kind {
                case .folder:
                    NavigationLink(value: IOSNetworkFolderRef(path: entry.path, name: entry.name)) {
                        IOSListRow(symbol: "folder", title: entry.name, detail: L10n.string("ios.local.folder"))
                    }
                case .film(let resource, _):
                    let watch = positions.state(for: .network(resource))
                    Button { playing = entry } label: {
                        IOSListRow(symbol: "film", title: entry.displayName, detail: detail(entry), watch: watch)
                            .id("\(entry.id)#\(watchRevision)")
                    }
                    .buttonStyle(.plain)
                    .contextMenu { watchToggle(.network(resource), isWatched: watch == .watched) }
                case .book:
                    IOSListRow(symbol: "book.closed", title: entry.name, detail: detail(entry))
                case .other:
                    IOSListRow(symbol: "doc", title: entry.name, detail: detail(entry))
                }
            }
        }
    }

    private func tiles(_ layout: IOSBrowseLayout) -> some View {
        ScrollView {
            if entries.isEmpty {
                empty.padding(IOSTheme.Spacing.large)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: layout.tileWidth ?? 104), spacing: IOSTheme.Spacing.medium)],
                spacing: IOSTheme.Spacing.large
            ) {
                ForEach(entries) { entry in
                    switch entry.kind {
                    case .folder:
                        NavigationLink(value: IOSNetworkFolderRef(path: entry.path, name: entry.name)) {
                            tile(entry, layout: layout)
                        }
                        .buttonStyle(.plain)
                    case .film:
                        Button { playing = entry } label: { tile(entry, layout: layout) }
                            .buttonStyle(.plain)
                    case .book, .other:
                        tile(entry, layout: layout)
                    }
                }
            }
            .padding(IOSTheme.Spacing.medium)
        }
    }

    private func tile(_ entry: IOSNetworkEntry, layout: IOSBrowseLayout) -> some View {
        let watch: WatchState? = if case .film(let resource, _) = entry.kind {
            positions.state(for: .network(resource))
        } else {
            nil
        }
        return VStack(spacing: IOSTheme.Spacing.tight) {
            ZStack {
                RoundedRectangle(cornerRadius: IOSTheme.Radius.card, style: .continuous)
                    .fill(Color.white.opacity(0.07))

                // Only the gallery reaches for artwork. In the icon layout a poster
                // would be too small to recognise and every tile would cost a request.
                if layout == .gallery, entry.posterURL != nil {
                    AsyncImage(url: entry.posterURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        symbol(for: entry)
                    }
                } else {
                    symbol(for: entry)
                }
            }
            .frame(height: layout == .gallery ? 200 : 84)
            .overlay(alignment: .topTrailing) {
                if watch == .new { IOSNewBadge().padding(IOSTheme.Spacing.tight) }
            }
            .overlay(alignment: .bottom) {
                if case .inProgress(let fraction)? = watch, fraction > 0 {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(IOSTheme.amber)
                            .frame(width: geometry.size.width * fraction, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: IOSTheme.Radius.card, style: .continuous))
            .opacity(watch == .watched ? 0.55 : 1)

            Text(entry.displayName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(watch == .watched ? IOSTheme.dim : .white)
        }
        .id("\(entry.id)#\(watchRevision)")
    }

    private func symbol(for entry: IOSNetworkEntry) -> some View {
        Image(systemName: symbolName(for: entry))
            .font(.title)
            .foregroundStyle(entry.isFolder ? IOSTheme.amber : IOSTheme.dim)
    }

    private func symbolName(for entry: IOSNetworkEntry) -> String {
        switch entry.kind {
        case .folder: "folder.fill"
        case .film: "film"
        case .book: "book.closed"
        case .other: "doc"
        }
    }

    // MARK: - Moving through the folder

    /// Every film in this folder, in list order.
    private func queue(startingWith resource: NetworkMediaResource, title: String) -> PlaybackQueue {
        let films = entries.compactMap { entry -> PlaybackQueueItem? in
            guard case .film(let film, let parsed) = entry.kind else { return nil }
            return PlaybackQueueItem(resource: film, title: parsed.listTitle)
        }
        return PlaybackQueue(items: films, current: PlaybackQueueItem(resource: resource, title: title))
    }

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

    // MARK: - Rows

    private func detail(_ entry: IOSNetworkEntry) -> String {
        var parts: [String] = []
        if let bytes = entry.byteCount, bytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        if case .film(let resource, _) = entry.kind, !resource.subtitleResources.isEmpty {
            parts.append(
                String(
                    format: L10n.string("ios.device.subtitle_count_format"),
                    resource.subtitleResources.count
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    private func preferredSubtitle(for resource: NetworkMediaResource) -> URL? {
        guard preferences.automaticallySelectSubtitles else { return nil }
        let wanted = preferences.defaultSubtitleLanguageCode
        return resource.subtitleResources.first { $0.languageCode == wanted }?.url
            ?? resource.subtitleResources.first?.url
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.small) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(IOSTheme.dim)
            Text(L10n.string("ios.network.folder_empty"))
                .font(.callout)
                .foregroundStyle(IOSTheme.dim)
        }
        .padding(.vertical, IOSTheme.Spacing.medium)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: IOSTheme.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(IOSTheme.amber)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(IOSTheme.dim)
            Button(L10n.string("network.browser.retry")) { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(IOSTheme.amber)
        }
        .padding(IOSTheme.Spacing.section)
    }

    private func load() async {
        phase = entries.isEmpty ? .loading : phase
        do {
            entries = try await browser.read(folder.path)
            phase = .ready
        } catch {
            phase = .failed(IOSLibraryModel.message(forSynology: error))
        }
    }
}
