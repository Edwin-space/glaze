import GlazeCore
import SwiftUI

/// What you get after choosing a film, before it starts.
///
/// Plex puts a screen here and it earns its place: a NAS folder is full of names that
/// differ by one word, and starting the wrong three-hour film is a worse outcome than
/// one extra click. It is also the only place with room to say what the file actually
/// is — the codec and container that decide whether it will play at all.
struct TVDetailView: View {
    let item: PlayableItem
    let resumeTime: TimeInterval?
    let onPlay: (TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TVTheme.signature(for: item.title).ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.35), TVTheme.ground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 80) {
                details
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 70)
        }
        .onExitCommand { dismiss() }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer(minLength: 0)

            Text(item.parsed.title)
                .font(.system(size: 68, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .frame(maxWidth: 1100, alignment: .leading)

            HStack(spacing: 12) {
                if let year = item.parsed.year {
                    Text(String(year))
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(TVTheme.dim)
                }
                if let episode = episodeLabel {
                    TVChip(text: episode)
                }
                if let runtime = runtimeLabel {
                    TVChip(text: runtime)
                }
                ForEach(item.parsed.badges, id: \.self) { badge in
                    TVChip(text: badge, emphasized: badge == "4K")
                }
            }

            HStack(spacing: 24) {
                Button {
                    onPlay(0)
                } label: {
                    Label(
                        L10n.string(resumeTime == nil ? "tv.detail.play" : "tv.detail.play_from_start"),
                        systemImage: "play.fill"
                    )
                }

                if let resumeTime {
                    Button {
                        onPlay(resumeTime)
                    } label: {
                        Label(
                            String(format: L10n.string("tv.detail.resume_format"), timecode(resumeTime)),
                            systemImage: "arrow.trianglehead.clockwise"
                        )
                    }
                }
            }
            .padding(.top, 10)

            fileFacts
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
    }

    /// The original name and the technical detail, small and out of the way. Someone
    /// looking for it is looking for a reason a film will not play.
    private var fileFacts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .lineLimit(2)
            HStack(spacing: 18) {
                if let resolution = item.resource.resolution { Text(resolution) }
                if let container = containerLabel { Text(container) }
                if let size = sizeLabel { Text(size) }
            }
        }
        .font(.system(size: 21))
        .foregroundStyle(.white.opacity(0.4))
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private var episodeLabel: String? {
        guard let season = item.parsed.season else { return nil }
        guard let episode = item.parsed.episode else { return String(format: "S%02d", season) }
        return String(format: "S%02dE%02d", season, episode)
    }

    private var runtimeLabel: String? {
        guard let duration = item.resource.duration, duration > 0 else { return nil }
        let minutes = Int(duration / 60)
        return String(format: L10n.string("tv.detail.minutes_format"), minutes)
    }

    private var containerLabel: String? {
        item.resource.mimeType?.split(separator: "/").last.map { $0.replacingOccurrences(of: "x-", with: "").uppercased() }
    }

    private var sizeLabel: String? {
        guard let bytes = item.resource.byteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)시간 \(minutes)분" : "\(minutes)분"
    }
}
