import GlazeCore
import SwiftUI

/// What you get after choosing a film, before it starts.
///
/// A NAS folder is full of names that differ by one word, and starting the wrong
/// three-hour film is a worse outcome than one extra click. Now that the Mac's poster
/// and plot travel with the film, this is also where they are read.
struct TVDetailView: View {
    let item: MediaLibraryItem
    let resource: NetworkMediaResource?
    @Bindable var preferences: TVUserPreferences

    @Environment(TVArtworkLoader.self) private var artwork
    @Environment(\.dismiss) private var dismiss
    @State private var positions = PlaybackPositionStore()
    @State private var startAt: TimeInterval?
    @State private var isPlaying = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop

            HStack(alignment: .top, spacing: 60) {
                TVPosterCard(
                    title: item.displayTitle,
                    subtitle: nil,
                    posterURL: item.posterURL,
                    width: 340
                )
                .allowsHitTesting(false)

                details

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 80)
        }
        .onExitCommand { dismiss() }
        .fullScreenCover(isPresented: $isPlaying) {
            if let resource {
                TVPlayerView(
                    resource: resource,
                    title: item.displayTitle,
                    startAt: startAt ?? 0,
                    preferredSubtitleLanguageCode: preferences.defaultSubtitleLanguageCode,
                    automaticallySelectSubtitles: preferences.automaticallySelectSubtitles,
                    preferredSubtitleScale: preferences.subtitleScale
                )
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            if let image = artwork.image(for: item.posterURL) {
                image.resizable().aspectRatio(contentMode: .fill).blur(radius: 70).opacity(0.45)
            } else {
                TVTheme.signature(for: item.displayTitle)
            }
            LinearGradient(
                colors: [TVTheme.ground.opacity(0.4), TVTheme.ground],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear { artwork.loadIfNeeded(item.posterURL) }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(item.displayTitle)
                .font(.system(size: 64, weight: .bold))
                .lineLimit(3)
                .frame(maxWidth: 1000, alignment: .leading)

            if let original = item.metadata?.originalTitle, original != item.displayTitle {
                Text(original)
                    .font(.system(size: 27))
                    .foregroundStyle(TVTheme.dim)
            }

            HStack(spacing: 12) {
                if let year = item.year {
                    Text(String(year))
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                if let rating = item.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(TVTheme.amber)
                }
                if let runtime = runtimeLabel {
                    TVChip(text: runtime)
                }
                if let episode = item.episodeLabel {
                    TVChip(text: episode)
                }
                ForEach(item.genres.prefix(3), id: \.self) { genre in
                    TVChip(text: genre)
                }
                ForEach(item.parsed.badges, id: \.self) { badge in
                    TVChip(text: badge, emphasized: badge == "4K")
                }
            }

            if let plot = item.plot, !plot.isEmpty {
                Text(plot)
                    .font(.system(size: 25))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(6)
                    .frame(maxWidth: 1000, alignment: .leading)
            }

            actions
            subtitleNote
            fileFacts.padding(.top, 12)

            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        HStack(spacing: 24) {
            Button {
                startAt = nil
                isPlaying = true
            } label: {
                Label(
                    L10n.string(resumeTime == nil ? "tv.detail.play" : "tv.detail.play_from_start"),
                    systemImage: "play.fill"
                )
            }

            if let resumeTime {
                Button {
                    startAt = resumeTime
                    isPlaying = true
                } label: {
                    Label(
                        String(format: L10n.string("tv.detail.resume_format"), timecode(resumeTime)),
                        systemImage: "arrow.trianglehead.clockwise"
                    )
                }
            }
        }
        .padding(.top, 8)
    }

    /// The subtitle the Mac put beside the film is the reason this product exists; if
    /// one travelled with it, say so before the viewer starts guessing.
    @ViewBuilder
    private var subtitleNote: some View {
        if !item.subtitleURLs.isEmpty {
            Label(
                String(format: L10n.string("tv.detail.subtitles_found_format"), item.subtitleURLs.count),
                systemImage: "captions.bubble"
            )
            .font(.system(size: 22))
            .foregroundStyle(TVTheme.amber)
        }
    }

    private var fileFacts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.sourceName).lineLimit(2)
            HStack(spacing: 18) {
                if let resolution = resource?.resolution { Text(resolution) }
                if let size = sizeLabel { Text(size) }
            }
        }
        .font(.system(size: 20))
        .foregroundStyle(.white.opacity(0.4))
        .frame(maxWidth: 1000, alignment: .leading)
    }

    private var resumeTime: TimeInterval? {
        guard let resource else { return nil }
        return positions.position(for: .network(resource))
    }

    private var runtimeLabel: String? {
        if let minutes = item.metadata?.runtimeMinutes, minutes > 0 {
            return String(format: L10n.string("tv.detail.minutes_format"), minutes)
        }
        guard let duration = item.duration ?? resource?.duration, duration > 0 else { return nil }
        return String(format: L10n.string("tv.detail.minutes_format"), Int(duration / 60))
    }

    private var sizeLabel: String? {
        guard let bytes = item.byteCount ?? resource?.byteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0
            ? String(format: L10n.string("tv.detail.timecode_hours_format"), hours, minutes)
            : String(format: L10n.string("tv.detail.timecode_minutes_format"), minutes)
    }
}
