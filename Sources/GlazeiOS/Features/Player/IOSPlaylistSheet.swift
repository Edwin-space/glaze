import GlazeCore
import SwiftUI

/// The rest of the folder, over the film.
///
/// Opened from the player rather than by closing it: the reason to look is to pick the
/// next thing, and going back to the list to do that stops the film and forgets where
/// the viewer was in the folder.
struct IOSPlaylistSheet: View {
    let queue: PlaybackQueue
    let positions: PlaybackPositionStore
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(queue.items.enumerated()), id: \.element.id) { offset, item in
                        Button { onChoose(item.id) } label: { row(item, number: offset + 1) }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                offset == queue.index ? IOSTheme.amber.opacity(0.14) : Color.clear
                            )
                            .id(item.id)
                    }
                }
                .glazeListBackground()
                // A folder of ninety episodes opened at episode sixty should show
                // episode sixty, not the top of the list.
                .onAppear { proxy.scrollTo(queue.current?.id, anchor: .center) }
            }
            .navigationTitle(L10n.string("ios.player.playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.close")) { dismiss() }
                }
            }
        }
    }

    private func row(_ item: PlaybackQueueItem, number: Int) -> some View {
        let isCurrent = item.id == queue.current?.id
        let watch = positions.state(for: .network(item.resource))
        return HStack(spacing: IOSTheme.Spacing.medium) {
            Group {
                if isCurrent {
                    Image(systemName: "play.fill").foregroundStyle(IOSTheme.amber)
                } else {
                    Text("\(number)").foregroundStyle(IOSTheme.dim)
                }
            }
            .font(.callout.monospacedDigit().weight(.semibold))
            .frame(width: 28)

            VStack(alignment: .leading, spacing: IOSTheme.Spacing.hair) {
                HStack(spacing: IOSTheme.Spacing.tight) {
                    Text(item.title)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(titleColor(isCurrent: isCurrent, watch: watch))
                        .lineLimit(2)
                    if watch == .new, !isCurrent { IOSNewBadge() }
                }
                if case .inProgress(let fraction) = watch, fraction > 0 {
                    ProgressView(value: fraction)
                        .tint(IOSTheme.amber)
                        .frame(maxWidth: 140)
                }
            }
            Spacer(minLength: 0)
            if watch == .watched, !isCurrent {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IOSTheme.dim)
            }
        }
        .padding(.vertical, IOSTheme.Spacing.tight)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// The film playing is amber; watched ones step back; the rest read normally.
    private func titleColor(isCurrent: Bool, watch: WatchState) -> Color {
        if isCurrent { return IOSTheme.amber }
        return watch == .watched ? IOSTheme.dim : .white
    }
}
