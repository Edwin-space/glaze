import GlazeCore
import SwiftUI

/// Where to go next inside a server.
struct TVNetworkFolder: Hashable {
    let path: String
    let name: String
}

/// A folder on a server, as the server reports it.
///
/// The shelves elsewhere in this app are built by reading the whole tree, which is the
/// right shape for a library someone has arranged and the wrong one for finding a file
/// on a NAS with thousands of them: nothing appears until everything has been read, and
/// it is read again on every connect. This asks for one folder and shows it.
struct TVNetworkBrowserView: View {
    let browser: TVNetworkBrowser
    let folder: TVNetworkFolder
    /// The film chosen, and every film in this folder around it.
    let onPlay: (PlaybackQueue) -> Void
    /// Bumped by the shell when the player closes, so NEW and watched marks catch up.
    var watchRevision = 0

    @State private var entries: [NetworkFolderEntry] = []
    @State private var phase: Phase = .loading
    private let positions = PlaybackPositionStore()

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(folder.name.isEmpty ? browser.serverName : folder.name)
                    .font(.system(size: 52, weight: .bold))
                Text(browser.serverName)
                    .font(.system(size: 25))
                    .foregroundStyle(TVTheme.dim)
            }

            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 84)
        .padding(.top, 70)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TVTheme.ground.ignoresSafeArea())
        .task(id: folder.path) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 20) {
                ProgressView().controlSize(.large)
                Text(L10n.string("tv.library.folder.reading"))
                    .font(.system(size: 27))
                    .foregroundStyle(TVTheme.dim)
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 25))
                .foregroundStyle(TVTheme.dim)
                .frame(maxWidth: 1100, alignment: .leading)
        case .ready:
            if entries.isEmpty {
                Text(L10n.string("ios.network.folder_empty"))
                    .font(.system(size: 25))
                    .foregroundStyle(TVTheme.dim)
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: NetworkFolderEntry) -> some View {
        switch entry.kind {
        case .folder:
            NavigationLink(value: TVNetworkFolder(path: entry.path, name: entry.name)) {
                rowLabel(entry, symbol: "folder", detail: nil, showsChevron: true, watch: nil)
            }
            .buttonStyle(.card)
        case .film(let resource, let parsed):
            Button { onPlay(queue(startingWith: resource, title: parsed.listTitle)) } label: {
                rowLabel(
                    entry,
                    symbol: "film",
                    detail: size(of: entry),
                    showsChevron: false,
                    watch: positions.state(for: .network(resource))
                )
                .id("\(entry.id)#\(watchRevision)")
            }
            .buttonStyle(.card)
        case .file:
            EmptyView()
        }
    }

    private func rowLabel(
        _ entry: NetworkFolderEntry,
        symbol: String,
        detail: String?,
        showsChevron: Bool,
        watch: WatchState?
    ) -> some View {
        HStack(spacing: 22) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(watch == .watched ? TVTheme.dim : TVTheme.amber)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Text(entry.displayName)
                        .font(.system(size: 30, weight: .medium))
                        // Watched episodes step back; the ones still to see stand out.
                        .foregroundStyle(watch == .watched ? TVTheme.dim : .white)
                        .lineLimit(1)
                    if watch == .new { TVNewBadge() }
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 22))
                        .foregroundStyle(TVTheme.dim)
                }
                if case .inProgress(let fraction)? = watch, fraction > 0 {
                    ProgressView(value: fraction)
                        .tint(TVTheme.amber)
                        .frame(maxWidth: 320)
                }
            }
            Spacer()
            if watch == .watched {
                Image(systemName: "checkmark").foregroundStyle(TVTheme.dim)
            }
            if showsChevron {
                Image(systemName: "chevron.right").foregroundStyle(TVTheme.dim)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every film in this folder, in list order, so episode two follows episode one.
    private func queue(startingWith resource: NetworkMediaResource, title: String) -> PlaybackQueue {
        let films = entries.compactMap { entry -> PlaybackQueueItem? in
            guard case .film(let film, let parsed) = entry.kind else { return nil }
            return PlaybackQueueItem(resource: film, title: parsed.listTitle)
        }
        return PlaybackQueue(items: films, current: PlaybackQueueItem(resource: resource, title: title))
    }

    private func size(of entry: NetworkFolderEntry) -> String? {
        guard let bytes = entry.byteCount, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func load() async {
        do {
            entries = try await browser.read(folder.path)
            phase = .ready
        } catch {
            phase = .failed(TVLibraryModel.message(for: error))
        }
    }
}
