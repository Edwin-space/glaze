import Foundation
import GlazeCore
import Observation

@MainActor
@Observable
final class PlaylistStore {
    var items: [MediaPlaylistItem] = []

    func setInitial(_ items: [MediaPlaylistItem]) {
        self.items = items
    }

    /// Scans the full sibling folder in the background and adopts the result only if the
    /// original video is still the one loaded and the scan actually found more items.
    func expandInBackground(for sourceURL: URL, currentItem: URL, isStillCurrent: @escaping () -> Bool) {
        guard !MediaPlaylistBuilder.isDirectory(sourceURL) else {
            return
        }

        Task {
            let expandedPlaylist = await Task.detached(priority: .utility) {
                MediaPlaylistBuilder.playlist(for: sourceURL)
            }.value

            guard isStillCurrent(), expandedPlaylist.count > items.count else {
                return
            }

            items = expandedPlaylist
        }
    }
}
