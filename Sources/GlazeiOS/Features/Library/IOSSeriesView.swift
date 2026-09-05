import GlazeCore
import SwiftUI

/// A show: its seasons, and the episodes in the one chosen.
struct IOSSeriesView: View {
    let series: MediaLibrarySeries
    let library: IOSLibraryModel

    @Environment(\.dismiss) private var dismiss
    @Environment(IOSArtworkLoader.self) private var artwork
    @State private var selectedSeason: Int
    @State private var playing: MediaLibraryItem?

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
                    Button { playing = episode } label: { row(for: episode) }
                }
            }
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.string("common.close")) { dismiss() }
            }
        }
        .fullScreenCover(item: $playing) { episode in
            if let resource = library.resource(for: episode) {
                IOSPlayerView(
                    resource: resource,
                    title: "\(series.title) · \(episode.episodeLabel ?? "")"
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            IOSPosterCard(title: series.title, subtitle: nil, posterURL: series.posterURL)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.episodeDisplayTitle).font(.callout).lineLimit(1)
                if let plot = episode.plot, !plot.isEmpty {
                    Text(plot).font(.caption2).foregroundStyle(IOSTheme.dim).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle").foregroundStyle(IOSTheme.amber)
        }
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
