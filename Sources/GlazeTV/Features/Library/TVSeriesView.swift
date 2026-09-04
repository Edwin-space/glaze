import GlazeCore
import SwiftUI

/// A show: what it is, then its seasons, then the episodes in the one you picked.
///
/// The point of the whole library index. These files used to sit on the shelf as
/// twenty-four separate tiles all called the same thing with a different number.
struct TVSeriesView: View {
    let series: MediaLibrarySeries
    let library: TVLibraryModel
    @Bindable var preferences: TVUserPreferences

    @Environment(TVArtworkLoader.self) private var artwork
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSeason: Int
    @State private var playing: MediaLibraryItem?
    @State private var positions = PlaybackPositionStore()

    init(series: MediaLibrarySeries, library: TVLibraryModel, preferences: TVUserPreferences) {
        self.series = series
        self.library = library
        self._preferences = Bindable(wrappedValue: preferences)
        self._selectedSeason = State(initialValue: series.seasons.first?.number ?? 1)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    seasonPicker
                    episodeList
                }
                .padding(.horizontal, 76)
                .padding(.top, 60)
                .padding(.bottom, 90)
            }
        }
        .onExitCommand { dismiss() }
        .fullScreenCover(item: $playing) { episode in
            player(for: episode)
        }
    }

    private var backdrop: some View {
        ZStack {
            if let posterURL = series.posterURL, let image = artwork.image(for: posterURL) {
                image.resizable().aspectRatio(contentMode: .fill).blur(radius: 70).opacity(0.45)
            } else {
                TVTheme.signature(for: series.title)
            }
            LinearGradient(
                colors: [TVTheme.ground.opacity(0.35), TVTheme.ground],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 700)
        .clipped()
        .ignoresSafeArea()
        .onAppear { artwork.loadIfNeeded(series.posterURL) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 44) {
            TVPosterCard(
                title: series.title,
                subtitle: nil,
                posterURL: series.posterURL,
                width: 300
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                Text(series.title)
                    .font(.system(size: 58, weight: .bold))
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if let year = series.year {
                        Text(String(year))
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    TVChip(
                        text: String(
                            format: L10n.string("tv.library.season_count_format"),
                            series.seasons.count
                        )
                    )
                    TVChip(
                        text: String(
                            format: L10n.string("tv.library.episode_count_format"),
                            series.episodeCount
                        )
                    )
                    ForEach(series.genres.prefix(3), id: \.self) { genre in
                        TVChip(text: genre)
                    }
                }

                if let plot = series.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(4)
                        .frame(maxWidth: 900, alignment: .leading)
                }

                if let next = nextToWatch {
                    Button { playing = next } label: {
                        Label(
                            String(
                                format: L10n.string("tv.library.play_episode_format"),
                                next.episodeLabel ?? ""
                            ),
                            systemImage: "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .padding(.top, 6)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(series.seasons) { season in
                    Button { selectedSeason = season.number } label: {
                        TVSeasonChip(
                            label: seasonLabel(season.number),
                            isSelected: season.number == selectedSeason
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
    }

    private var episodeList: some View {
        VStack(spacing: 18) {
            ForEach(episodes) { episode in
                Button { playing = episode } label: {
                    TVEpisodeRow(episode: episode, progress: progress(for: episode))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func player(for episode: MediaLibraryItem) -> some View {
        if let resource = library.resource(for: episode) {
            TVPlayerView(
                resource: resource,
                title: "\(series.title) · \(episode.episodeLabel ?? "")",
                startAt: positions.position(for: .network(resource)) ?? 0,
                preferredSubtitleLanguageCode: preferences.defaultSubtitleLanguageCode,
                automaticallySelectSubtitles: preferences.automaticallySelectSubtitles,
                preferredSubtitleScale: preferences.subtitleScale
            )
        }
    }

    private var episodes: [MediaLibraryItem] {
        series.seasons.first { $0.number == selectedSeason }?.episodes ?? []
    }

    /// Where the viewer left off, or the first episode if they never started.
    private var nextToWatch: MediaLibraryItem? {
        let started = series.allEpisodes.first { progress(for: $0) != nil }
        return started ?? series.allEpisodes.first
    }

    private func seasonLabel(_ number: Int) -> String {
        switch number {
        case 0: L10n.string("tv.library.specials")
        case ..<0: L10n.string("tv.library.other_episodes")
        default: String(format: L10n.string("tv.library.season_format"), number)
        }
    }

    private func progress(for episode: MediaLibraryItem) -> Double? {
        guard let resource = library.resource(for: episode),
              let time = positions.position(for: .network(resource)),
              let duration = episode.duration ?? resource.duration,
              duration > 0
        else { return nil }
        return time / duration
    }
}

private struct TVSeasonChip: View {
    let label: String
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(label)
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(isFocused ? .black : (isSelected ? TVTheme.amber : .white.opacity(0.8)))
            .padding(.horizontal, 26)
            .frame(height: 58)
            .background(
                Capsule().fill(
                    isFocused ? .white : (isSelected ? TVTheme.amber.opacity(0.18) : .white.opacity(0.08))
                )
            )
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

private struct TVEpisodeRow: View {
    let episode: MediaLibraryItem
    let progress: Double?

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 26) {
            Text(episode.episodeNumber.map { String(format: "%02d", $0) } ?? "–")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(isFocused ? .black.opacity(0.55) : TVTheme.dim)
                .frame(width: 60, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                Text(episode.episodeDisplayTitle)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isFocused ? .black : .white)
                    .lineLimit(1)

                if let plot = episode.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.system(size: 21))
                        .foregroundStyle(isFocused ? .black.opacity(0.7) : TVTheme.dim)
                        .lineLimit(2)
                }

                if let progress {
                    ZStack(alignment: .leading) {
                        Capsule().fill(isFocused ? .black.opacity(0.2) : .white.opacity(0.2))
                        GeometryReader { geometry in
                            Capsule()
                                .fill(isFocused ? .black : TVTheme.amber)
                                .frame(width: geometry.size.width * min(1, progress))
                        }
                    }
                    .frame(height: 5)
                    .frame(maxWidth: 420)
                }
            }

            Spacer(minLength: 0)

            if let runtime = episode.metadata?.runtimeMinutes {
                Text(String(format: L10n.string("tv.library.runtime_format"), runtime))
                    .font(.system(size: 21))
                    .foregroundStyle(isFocused ? .black.opacity(0.6) : TVTheme.dim)
            }

            Image(systemName: "play.fill")
                .font(.system(size: 26))
                .foregroundStyle(isFocused ? .black : TVTheme.dim)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? .white : .white.opacity(0.06))
        )
        .scaleEffect(isFocused ? 1.015 : 1)
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}
