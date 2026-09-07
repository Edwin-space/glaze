import GlazeCore
import SwiftUI

/// A show: its seasons, and the episodes in the one chosen.
struct IOSSeriesView: View {
    let series: MediaLibrarySeries
    let library: IOSLibraryModel

    @Environment(IOSUserPreferences.self) private var preferences
    @State private var selectedSeason: Int
    @State private var playing: PlayRequest?
    @State private var positions = PlaybackPositionStore()

    /// An episode and where to start it — the row resumes, the menu starts over.
    private struct PlayRequest: Identifiable, Equatable {
        let episode: MediaLibraryItem
        let startAt: TimeInterval
        var id: String { "\(episode.id)@\(Int(startAt))" }
    }

    init(series: MediaLibrarySeries, library: IOSLibraryModel) {
        self.series = series
        self.library = library
        _selectedSeason = State(initialValue: series.seasons.first?.number ?? 1)
    }

    var body: some View {
        List {
            Section {
                header.listRowInsets(EdgeInsets())
            }

            if series.seasons.count > 1 {
                Section {
                    Picker(L10n.string("tv.library.season_format"), selection: $selectedSeason) {
                        ForEach(series.seasons) { season in
                            Text(seasonLabel(season.number)).tag(season.number)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                ForEach(episodes) { episode in
                    Button { play(episode, fromStart: false) } label: { row(for: episode) }
                        .contextMenu {
                            Button(L10n.string("tv.detail.play_from_start"), systemImage: "play.fill") {
                                play(episode, fromStart: true)
                            }
                        }
                }
            }
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { request in
            player(for: request)
        }
    }

    @ViewBuilder
    private func player(for request: PlayRequest) -> some View {
        if let resource = library.resource(for: request.episode) {
            IOSPlayerView(
                resource: resource,
                title: "\(series.title) · \(request.episode.episodeLabel ?? request.episode.episodeDisplayTitle)",
                startAt: request.startAt,
                subtitleURL: IOSSubtitleChoice.preferred(
                    among: resource.subtitleResources,
                    language: preferences.defaultSubtitleLanguageCode
                ),
                subtitleCandidates: { [library, episode = request.episode] in
                    await library.subtitleCandidates(for: episode)
                },
                upNext: upNext(after: request.episode)
            )
        } else {
            IOSUnplayableView(name: request.episode.sourceName)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            IOSPosterCard(
                title: series.title,
                subtitle: nil,
                posterURL: series.posterURL,
                showsCaption: false
            )
            .frame(width: 96)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text(series.title).font(.headline)
                HStack(spacing: 6) {
                    if let year = series.year {
                        Text(String(year)).font(.caption).foregroundStyle(IOSTheme.dim)
                    }
                    IOSChip(
                        text: String(
                            format: L10n.string("tv.library.episode_count_format"),
                            series.episodeCount
                        )
                    )
                }
                if let plot = series.plot, !plot.isEmpty {
                    Text(plot).font(.caption).foregroundStyle(IOSTheme.dim).lineLimit(5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func row(for episode: MediaLibraryItem) -> some View {
        HStack(spacing: 12) {
            Text(episode.episodeNumber.map { String(format: "%02d", $0) } ?? "–")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(IOSTheme.dim)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(episode.episodeDisplayTitle).font(.callout).lineLimit(1)
                if let plot = episode.plot, !plot.isEmpty {
                    Text(plot).font(.caption2).foregroundStyle(IOSTheme.dim).lineLimit(2)
                }
                // How far in the viewer got, so a half-watched episode is obvious
                // without opening it.
                if let fraction = progress(for: episode) {
                    ProgressView(value: fraction)
                        .tint(IOSTheme.amber)
                        .frame(maxWidth: 140)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle").foregroundStyle(IOSTheme.amber)
        }
    }

    // MARK: - Playing

    private func play(_ episode: MediaLibraryItem, fromStart: Bool) {
        let resume = fromStart ? 0 : (resumeTime(for: episode) ?? 0)
        playing = PlayRequest(episode: episode, startAt: resume)
    }

    /// The next episode in the same season, offered from inside the player so a series
    /// does not stop dead at the end of every file.
    private func upNext(after episode: MediaLibraryItem) -> IOSUpNext? {
        let ordered = episodes
        guard let index = ordered.firstIndex(where: { $0.id == episode.id }),
              ordered.indices.contains(index + 1)
        else { return nil }
        let next = ordered[index + 1]
        return IOSUpNext(title: next.episodeDisplayTitle) {
            playing = PlayRequest(episode: next, startAt: 0)
        }
    }

    private func resumeTime(for episode: MediaLibraryItem) -> TimeInterval? {
        guard let resource = library.resource(for: episode) else { return nil }
        return positions.position(for: .network(resource))
    }

    private func progress(for episode: MediaLibraryItem) -> Double? {
        guard let time = resumeTime(for: episode),
              let duration = episode.duration, duration > 0 else { return nil }
        return time / duration
    }

    private var episodes: [MediaLibraryItem] {
        series.seasons.first { $0.number == selectedSeason }?.episodes ?? []
    }

    private func seasonLabel(_ number: Int) -> String {
        switch number {
        case 0: L10n.string("tv.library.specials")
        case ..<0: L10n.string("tv.library.other_episodes")
        default: String(format: L10n.string("tv.library.season_format"), number)
        }
    }
}
