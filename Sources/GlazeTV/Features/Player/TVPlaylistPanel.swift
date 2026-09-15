import GlazeCore
import SwiftUI

/// The rest of the folder, beside the film.
///
/// Opened without stopping anything: the reason to look is to pick what comes next,
/// and going back to the folder to do that loses the place in it.
struct TVPlaylistPanel: View {
    let queue: PlaybackQueue
    let onChoose: (String) -> Void
    let onClose: () -> Void

    private let positions = PlaybackPositionStore()
    @FocusState private var focused: String?

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.string("ios.player.playlist"))
                    .font(.system(size: 38, weight: .bold))

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(queue.items.enumerated()), id: \.element.id) { offset, item in
                                row(item, number: offset + 1).id(item.id)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    // A run of ninety episodes opened at sixty should start at sixty.
                    .onAppear {
                        proxy.scrollTo(queue.current?.id, anchor: .center)
                        focused = queue.current?.id
                    }
                }
            }
            .padding(40)
            .frame(width: 720)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
            .padding(.vertical, 60)
            .padding(.trailing, 60)
        }
    }

    private func row(_ item: PlaybackQueueItem, number: Int) -> some View {
        let isCurrent = item.id == queue.current?.id
        let watch = positions.state(for: .network(item.resource))
        return Button { onChoose(item.id) } label: {
            HStack(spacing: 20) {
                Group {
                    if isCurrent {
                        Image(systemName: "play.fill").foregroundStyle(TVTheme.amber)
                    } else {
                        Text("\(number)").foregroundStyle(TVTheme.dim)
                    }
                }
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .frame(width: 44)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(item.title)
                            .font(.system(size: 27, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? TVTheme.amber : (watch == .watched ? TVTheme.dim : .white))
                            .lineLimit(1)
                        if watch == .new, !isCurrent { TVNewBadge() }
                    }
                    if case .inProgress(let fraction) = watch, fraction > 0 {
                        ProgressView(value: fraction)
                            .tint(TVTheme.amber)
                            .frame(maxWidth: 260)
                    }
                }
                Spacer(minLength: 0)
                if watch == .watched, !isCurrent {
                    Image(systemName: "checkmark").foregroundStyle(TVTheme.dim)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.card)
        .focused($focused, equals: item.id)
    }
}

/// "NEW", beside an episode nobody has started — the same mark the phone uses.
struct TVNewBadge: View {
    var body: some View {
        Text(L10n.string("ios.watch.new_badge"))
            .font(.system(size: 15, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(TVTheme.amber, in: Capsule())
            .accessibilityHidden(true)
    }
}
