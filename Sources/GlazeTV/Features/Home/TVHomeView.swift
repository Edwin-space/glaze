import GlazeCore
import SwiftUI

/// Content-first launch surface modeled on the Apple TV app's cinematic Home.
struct TVHomeView: View {
    let model: NetworkMediaBrowserModel
    @Bindable var preferences: TVUserPreferences
    let onOpenSources: () -> Void

    @State private var positions = PlaybackPositionStore()
    @State private var route: Route?

    var body: some View {
        ZStack(alignment: .topLeading) {
            heroBackdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 42) {
                    hero
                        .frame(height: 590)

                    if !resumable.isEmpty {
                        shelf(L10n.string("tv.home.continue"), items: resumable)
                    }

                    if !videos.isEmpty {
                        shelf(L10n.string("tv.home.recent"), items: videos)
                    } else {
                        connectShelf
                    }
                }
                .padding(.bottom, 80)
            }
        }
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
                    startAt: startAt,
                    preferredSubtitleLanguageCode: preferences.defaultSubtitleLanguageCode,
                    automaticallySelectSubtitles: preferences.automaticallySelectSubtitles,
                    preferredSubtitleScale: preferences.subtitleScale
                )
            }
        }
    }

    private var heroBackdrop: some View {
        ZStack {
            if let featured {
                TVTheme.signature(for: featured.title)
            } else {
                LinearGradient(
                    colors: [TVTheme.amber.opacity(0.28), TVTheme.ground, .black],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }

            LinearGradient(
                colors: [.clear, TVTheme.ground.opacity(0.35), TVTheme.ground],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 760)
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Text(featured?.parsed.title ?? L10n.string("tv.home.welcome.title"))
                .font(.system(size: 72, weight: .bold))
                .lineLimit(2)
                .frame(maxWidth: 1050, alignment: .leading)

            Text(featuredDetail)
                .font(.system(size: 27))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(3)
                .frame(maxWidth: 960, alignment: .leading)

            if let featured {
                Button {
                    route = .detail(featured)
                } label: {
                    Label(L10n.string("tv.detail.play"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 8)
            } else {
                Button(action: onOpenSources) {
                    Label(L10n.string("tv.home.connect"), systemImage: "externaldrive.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 76)
    }

    private func shelf(_ title: String, items: [PlayableItem]) -> some View {
        TVShelf(title: title) {
            ForEach(items) { item in
                Button { route = .detail(item) } label: {
                    TVMediaCard(item: item, progress: progress(for: item))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var connectShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("tv.home.library.title"))
                .font(.system(size: 34, weight: .semibold))

            Button(action: onOpenSources) {
                HStack(spacing: 24) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 42))
                        .foregroundStyle(TVTheme.amber)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("tv.home.connect"))
                            .font(.system(size: 31, weight: .semibold))
                        Text(L10n.string("tv.home.connect.detail"))
                            .font(.system(size: 22))
                            .foregroundStyle(TVTheme.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(28)
                .frame(maxWidth: 1000, alignment: .leading)
            }
            .buttonStyle(.card)
        }
        .padding(.horizontal, 76)
    }

    private var videos: [PlayableItem] {
        model.currentNodes.compactMap { node in
            guard case .video(let resource) = node.kind else { return nil }
            return PlayableItem(resource: resource, title: node.title)
        }
    }

    private var resumable: [PlayableItem] {
        videos.filter { positions.position(for: .network($0.resource)) != nil }
    }

    private var featured: PlayableItem? {
        resumable.first ?? videos.first
    }

    private var featuredDetail: String {
        if let server = model.selectedServer {
            return String(format: L10n.string("tv.home.source.detail_format"), server.friendlyName)
        }
        return L10n.string("tv.home.welcome.detail")
    }

    private func resumeTime(for item: PlayableItem) -> TimeInterval? {
        positions.position(for: .network(item.resource))
    }

    private func progress(for item: PlayableItem) -> Double? {
        guard let time = resumeTime(for: item),
              let duration = item.resource.duration, duration > 0 else { return nil }
        return time / duration
    }
}
