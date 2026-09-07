import GlazeCore
import SwiftUI

/// What you get after choosing a film, before it starts.
///
/// A NAS folder is full of names that differ by one word, and starting the wrong
/// three-hour film is a worse outcome than one extra tap. It is also the only place the
/// poster and plot the Mac wrote beside the film are read at full size.
struct IOSDetailView: View {
    let item: MediaLibraryItem
    let library: IOSLibraryModel

    @Environment(IOSArtworkLoader.self) private var artwork
    @Environment(IOSUserPreferences.self) private var preferences
    @State private var positions = PlaybackPositionStore()
    @State private var startAt: TimeInterval?
    @State private var isPlaying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IOSTheme.Spacing.large) {
                header
                actions
                if let plot = item.plot, !plot.isEmpty {
                    Text(plot).font(.callout).foregroundStyle(.primary.opacity(0.85))
                }
                subtitleNote
                facts
            }
            .padding(.horizontal, IOSTheme.Spacing.large)
            .padding(.vertical, IOSTheme.Spacing.medium)
        }
        .background(IOSTheme.ground)
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isPlaying) {
            if let resource = library.resource(for: item) {
                IOSPlayerView(
                    resource: resource,
                    title: item.displayTitle,
                    startAt: startAt ?? 0,
                    subtitleURL: preferredSubtitleURL(for: resource),
                    subtitleCandidates: { [library, item] in await library.subtitleCandidates(for: item) }
                )
            } else {
                IOSUnplayableView(name: item.sourceName)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: IOSTheme.Spacing.medium) {
            IOSPosterCard(
                title: item.displayTitle,
                subtitle: nil,
                posterURL: item.posterURL,
                showsCaption: false
            )
            .frame(width: 118)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: IOSTheme.Spacing.tight) {
                Text(item.displayTitle).font(.title3.weight(.semibold)).lineLimit(3)

                if let original = item.metadata?.originalTitle, original != item.displayTitle {
                    Text(original).font(.footnote).foregroundStyle(IOSTheme.dim)
                }

                HStack(spacing: IOSTheme.Spacing.tight) {
                    if let year = item.year {
                        Text(String(year)).font(.footnote).foregroundStyle(IOSTheme.dim)
                    }
                    if let rating = item.rating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(IOSTheme.amber)
                    }
                    if let runtime = runtimeLabel {
                        IOSChip(text: runtime)
                    }
                }

                if !badges.isEmpty {
                    HStack(spacing: IOSTheme.Spacing.tight) {
                        ForEach(badges, id: \.self) { IOSChip(text: $0) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        VStack(spacing: IOSTheme.Spacing.small) {
            if let resumeTime {
                Button {
                    startAt = resumeTime
                    isPlaying = true
                } label: {
                    Label(
                        String(format: L10n.string("tv.detail.resume_format"), timecode(resumeTime)),
                        systemImage: "arrow.trianglehead.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(IOSTheme.amber)
            }

            // The resume button takes the filled style when there is one, so the two
            // never compete for the same emphasis.
            if resumeTime == nil {
                Button(action: playFromStart) { playFromStartLabel }
                    .buttonStyle(.borderedProminent)
                    .tint(IOSTheme.amber)
            } else {
                Button(action: playFromStart) { playFromStartLabel }
                    .buttonStyle(.bordered)
                    .tint(IOSTheme.amber)
            }
        }
        .controlSize(.large)
    }

    private var playFromStartLabel: some View {
        Label(
            L10n.string(resumeTime == nil ? "tv.detail.play" : "tv.detail.play_from_start"),
            systemImage: "play.fill"
        )
        .frame(maxWidth: .infinity)
    }

    private func playFromStart() {
        startAt = nil
        isPlaying = true
    }

    /// The subtitle the Mac put beside the film is the reason this product exists; if
    /// one travelled with it, say so before the viewer starts guessing.
    @ViewBuilder
    private var subtitleNote: some View {
        if item.subtitleURLs.isEmpty {
            Label(L10n.string("ios.detail.no_subtitles"), systemImage: "captions.bubble")
                .font(.footnote)
                .foregroundStyle(IOSTheme.dim)
        } else {
            Label(
                String(format: L10n.string("tv.detail.subtitles_found_format"), item.subtitleURLs.count),
                systemImage: "captions.bubble"
            )
            .font(.footnote)
            .foregroundStyle(IOSTheme.amber)
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: IOSTheme.Spacing.hair) {
            Text(item.sourceName).lineLimit(2)
            if let size = sizeLabel { Text(size) }
        }
        .font(.caption2)
        .foregroundStyle(IOSTheme.dim)
    }

    // MARK: - Values

    private var badges: [String] {
        item.genres.prefix(2) + item.parsed.badges
    }

    private var resumeTime: TimeInterval? {
        guard let resource = library.resource(for: item) else { return nil }
        return positions.position(for: .network(resource))
    }

    private var runtimeLabel: String? {
        if let minutes = item.metadata?.runtimeMinutes, minutes > 0 {
            return String(format: L10n.string("tv.detail.minutes_format"), minutes)
        }
        guard let duration = item.duration, duration > 0 else { return nil }
        return String(format: L10n.string("tv.detail.minutes_format"), Int(duration / 60))
    }

    private var sizeLabel: String? {
        guard let bytes = item.byteCount else { return nil }
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

    private func preferredSubtitleURL(for resource: NetworkMediaResource) -> URL? {
        IOSSubtitleChoice.preferred(
            among: resource.subtitleResources,
            language: preferences.defaultSubtitleLanguageCode
        )
    }
}

/// Shown instead of a black screen when a library entry has no playable address —
/// a DLNA server that dropped the resource, or a scan that ran before a mount.
struct IOSUnplayableView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: IOSTheme.Spacing.medium) {
                Image(systemName: "questionmark.folder")
                    .font(.largeTitle)
                    .foregroundStyle(IOSTheme.amber)
                Text(L10n.string("ios.player.unplayable"))
                    .font(.callout)
                    .foregroundStyle(.white)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Button(L10n.string("common.close")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(IOSTheme.amber)
            }
            .padding(IOSTheme.Spacing.section)
        }
    }
}

/// Which of the subtitles beside a film to hand the player.
enum IOSSubtitleChoice {
    static func preferred(
        among resources: [NetworkSubtitleResource],
        language: String?
    ) -> URL? {
        guard !resources.isEmpty else { return nil }
        let wanted = language.flatMap(SubtitleLanguageCode.normalized)
            ?? SubtitleLanguagePreference.targetLanguageCode
        return resources.first { $0.languageCode.flatMap(SubtitleLanguageCode.normalized) == wanted }?.url
            ?? resources.first?.url
    }
}
