import GlazeCore
import SwiftUI

/// A NAS folder, seen over WebDAV.
///
/// The same shelves and cards the DLNA library uses, with one difference that is the
/// whole reason WebDAV is here: the subtitle sitting beside a film comes with it.
struct TVWebDAVLibraryView: View {
    let connection: WebDAVConnection
    @Bindable var preferences: TVUserPreferences

    @State private var model = WebDAVBrowserModel()
    @State private var route: WebDAVRoute?

    var body: some View {
        ZStack {
            TVTheme.ground.ignoresSafeArea()
            content
        }
        .task { await model.open(connection) }
        .fullScreenCover(item: $route) { route in
            switch route {
            case .playing(let entry, let subtitleURL):
                TVPlayerView(
                    resource: resource(for: entry),
                    title: MediaTitleParser.parse(entry.name).title,
                    externalSubtitleURL: subtitleURL,
                    preferredSubtitleLanguageCode: preferences.defaultSubtitleLanguageCode,
                    automaticallySelectSubtitles: preferences.automaticallySelectSubtitles,
                    preferredSubtitleScale: preferences.subtitleScale
                )
            }
        }
        .onExitCommand { model.navigateBack() }
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.errorMessage {
            failure(message)
        } else if model.phase == .loading {
            VStack(spacing: 28) {
                ProgressView().controlSize(.large)
                Text(L10n.string("network.browser.loading"))
                    .font(.title3)
                    .foregroundStyle(TVTheme.dim)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    Text(model.title)
                        .font(.system(size: 54, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 60)
                        .padding(.top, 44)

                    if !model.videos.isEmpty {
                        TVShelf(title: L10n.string("tv.home.videos")) {
                            ForEach(model.videos) { entry in
                                card(entry)
                            }
                        }
                    }

                    if !model.folders.isEmpty {
                        folderSection
                    }
                }
                .padding(.bottom, 60)
            }
        }
    }

    private func card(_ entry: WebDAVEntry) -> some View {
        Button {
            // The subtitle is chosen here rather than in the player: the folder listing
            // is what knows about it, and the player should not have to browse.
            let companions = model.companions(for: entry)
            route = .playing(entry, subtitle: preferredSubtitle(from: companions)?.url)
        } label: {
            TVMediaCard(item: item(for: entry), progress: nil)
        }
        .buttonStyle(.borderless)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("tv.home.folders"))
                .font(.system(size: 34, weight: .semibold))
                .padding(.horizontal, 60)

            VStack(spacing: 14) {
                ForEach(model.folders) { entry in
                    Button {
                        Task { await model.open(entry) }
                    } label: {
                        HStack(spacing: 22) {
                            Image(systemName: "folder.fill").foregroundStyle(TVTheme.amber)
                            Text(entry.name).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(TVTheme.dim)
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

    private func failure(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(TVTheme.dim)
            Text(message)
                .font(.title3)
                .foregroundStyle(TVTheme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
        }
    }

    /// The viewer's own language first; failing that, whatever is there.
    private func preferredSubtitle(from companions: WebDAVCompanions) -> WebDAVEntry? {
        let target = preferences.defaultSubtitleLanguageCode
        return companions.subtitles.first { entry in
            SubtitleFile.manual(url: entry.url).languageCode == target
        } ?? companions.subtitles.first
    }

    private func item(for entry: WebDAVEntry) -> PlayableItem {
        PlayableItem(
            resource: resource(for: entry),
            title: entry.name
        )
    }

    private func resource(for entry: WebDAVEntry) -> NetworkMediaResource {
        NetworkMediaResource(
            serverID: connection.id,
            objectID: entry.url.absoluteString,
            playbackURL: entry.url,
            byteCount: entry.byteCount,
            dateAdded: entry.lastModified
        )
    }
}

enum WebDAVRoute: Identifiable, Equatable {
    case playing(WebDAVEntry, subtitle: URL?)

    var id: String {
        switch self {
        case .playing(let entry, _): entry.id
        }
    }
}
