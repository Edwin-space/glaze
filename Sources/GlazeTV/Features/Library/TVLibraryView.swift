import GlazeCore
import SwiftUI

/// Finding something to watch, from the sofa.
///
/// Folders are a list and films are a shelf of tiles, because they are different kinds
/// of thing: a folder is a step on the way somewhere, and a film is the destination.
/// Giving both the same row treatment — which is what this screen did first — makes a
/// NAS look like a file browser projected onto a television.
struct TVLibraryView: View {
    @State private var model = NetworkMediaBrowserModel()
    @State private var positions = PlaybackPositionStore()
    /// One route at a time. Two `fullScreenCover` modifiers on the same view do not
    /// both work — the second silently never presents, which looked exactly like the
    /// remote's select button being ignored.
    @State private var route: Route?

    var body: some View {
        ZStack {
            TVTheme.ground.ignoresSafeArea()
            content
        }
        .task { await model.discoverIfNeeded() }
        .fullScreenCover(item: $route) { route in
            switch route {
            case .detail(let item):
                TVDetailView(item: item, resumeTime: resumeTime(for: item)) { startAt in
                    self.route = .playing(item, startAt: startAt)
                }
            case .playing(let item, let startAt):
                TVPlayerView(
                    resource: item.resource,
                    title: item.parsed.title,
                    startAt: startAt
                )
            }
        }
        .onExitCommand { model.navigateBack() }
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .discovering {
            waiting(L10n.string("network.browser.discovering"))
        } else if model.selectedServer == nil {
            serverList
        } else if model.phase == .browsing, model.currentNodes.isEmpty {
            waiting(L10n.string("network.browser.loading"))
        } else {
            browsingView
        }
    }

    // MARK: - Servers

    private var serverList: some View {
        Group {
            if model.servers.isEmpty {
                emptyState(
                    title: L10n.string("network.browser.empty"),
                    detail: L10n.string("network.browser.empty_hint")
                )
            } else {
                VStack(alignment: .leading, spacing: 30) {
                    Text(L10n.string("network.browser.title"))
                        .font(.system(size: 62, weight: .bold))
                        .padding(.horizontal, 60)
                        .padding(.top, 50)

                    ScrollView {
                        VStack(spacing: 22) {
                            ForEach(model.servers) { server in
                                Button {
                                    Task { await model.select(server) }
                                } label: {
                                    serverRow(server)
                                }
                                .buttonStyle(.card)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 20)
                    }
                }
            }
        }
    }

    private func serverRow(_ server: NetworkMediaServer) -> some View {
        HStack(spacing: 24) {
            Image(systemName: "externaldrive.connected.to.line.below.fill")
                .font(.system(size: 40))
                .foregroundStyle(TVTheme.amber)
            Text(server.friendlyName)
                .font(.system(size: 34, weight: .medium))
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inside a server

    private var browsingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Text(model.navigationTitle)
                    .font(.system(size: 54, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 60)
                    .padding(.top, 44)

                if !resumable.isEmpty {
                    TVShelf(title: L10n.string("tv.home.continue")) {
                        ForEach(resumable) { item in
                            card(item)
                        }
                    }
                }

                if !videos.isEmpty {
                    TVShelf(title: shelfTitle) {
                        ForEach(videos) { item in
                            card(item)
                        }
                    }
                }

                if !folders.isEmpty {
                    folderSection
                }
            }
            .padding(.bottom, 60)
        }
    }

    private func card(_ item: PlayableItem) -> some View {
        Button {
            route = .detail(item)
        } label: {
            TVMediaCard(item: item, progress: progress(for: item))
        }
        // Not a custom ButtonStyle. One that returns only its label does remove the
        // pale plate tvOS draws behind a focused button, but it also stops the button
        // ever firing — it looked exactly like the remote's select being ignored.
        // `.borderless` drops the plate and keeps the action.
        .buttonStyle(.borderless)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("tv.home.folders"))
                .font(.system(size: 34, weight: .semibold))
                .padding(.horizontal, 60)

            VStack(spacing: 14) {
                ForEach(folders, id: \.id) { node in
                    Button {
                        Task { await model.open(node) }
                    } label: {
                        HStack(spacing: 22) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(TVTheme.amber)
                            Text(MediaTitleParser.parse(node.title).title)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(TVTheme.dim)
                        }
                        .font(.system(size: 30))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 60)
        }
    }

    // MARK: - Content split

    private var folders: [NetworkMediaNode] {
        model.currentNodes.filter { if case .container = $0.kind { return true }; return false }
    }

    private var videos: [PlayableItem] {
        model.currentNodes.compactMap { node in
            guard case .video(let resource) = node.kind else { return nil }
            return PlayableItem(resource: resource, title: node.title)
        }
    }

    /// Films this viewer already started, newest progress first.
    private var resumable: [PlayableItem] {
        videos.filter { positions.position(for: .network($0.resource)) != nil }
    }

    /// Named for what the shelf is when the server bothered to date its files.
    private var shelfTitle: String {
        videos.contains { $0.resource.dateAdded != nil }
            ? L10n.string("tv.home.recent")
            : L10n.string("tv.home.videos")
    }

    private func resumeTime(for item: PlayableItem) -> TimeInterval? {
        positions.position(for: .network(item.resource))
    }

    private func progress(for item: PlayableItem) -> Double? {
        guard let time = resumeTime(for: item),
              let duration = item.resource.duration, duration > 0 else { return nil }
        return time / duration
    }

    // MARK: - States

    private func waiting(_ message: String) -> some View {
        VStack(spacing: 28) {
            ProgressView().controlSize(.large)
            Text(message)
                .font(.title3)
                .foregroundStyle(TVTheme.dim)
        }
    }

    private func emptyState(title: String, detail: String?) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 64))
                .foregroundStyle(TVTheme.dim)
            Text(title).font(.title2)
            if let detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(TVTheme.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 720)
            }
            Button(L10n.string("network.browser.refresh")) {
                Task { await model.discover() }
            }
            .padding(.top, 12)
        }
    }
}

/// Where the viewer is: looking at a film, or watching it. Playing carries where to
/// start, so "resume" and "from the beginning" are the same code path.
enum Route: Identifiable, Equatable {
    case detail(PlayableItem)
    case playing(PlayableItem, startAt: TimeInterval)

    var id: String {
        switch self {
        case .detail(let item): "detail:\(item.id)"
        case .playing(let item, let startAt): "play:\(item.id)@\(Int(startAt))"
        }
    }
}
