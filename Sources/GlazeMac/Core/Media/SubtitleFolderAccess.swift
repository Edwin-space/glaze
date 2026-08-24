import AppKit
import Foundation
import GlazeCore

/// Remembers folders the viewer has allowed Glaze to read subtitles from.
///
/// Under the App Sandbox, opening a film grants access to that one file. The `.srt`
/// beside it is a different file, and reading it is refused — so sidecar subtitles,
/// the ordinary way people have subtitles, do not work at all in the build that ships.
/// The `com.apple.security.assets.movies.read-write` entitlement covers `~/Movies`, but
/// films live on the Desktop, in Downloads, on external drives, and on mounted NAS
/// shares, which is where this product is headed (`docs/21_media_server_vision.md`).
///
/// The general answer macOS provides is a security-scoped bookmark: the viewer points
/// at the folder once, through a panel they control, and the grant survives restarts.
/// Asking is not ideal, but it is asked once per folder and the alternative is a
/// feature that silently does not work.
@MainActor
enum SubtitleFolderAccess {
    private static let defaultsKey = "subtitle.folderBookmarks"

    /// Folders currently being accessed, so `stopAccessing` is balanced and a folder is
    /// not opened twice.
    private static var active: [String: URL] = [:]

    /// Opens a folder Glaze was previously allowed to read, if there is a grant for it.
    ///
    /// - Returns: true when the folder is now readable.
    @discardableResult
    static func restoreAccess(toFolderOf videoURL: URL) -> Bool {
        let folder = videoURL.deletingLastPathComponent().standardizedFileURL
        let key = folder.path

        if active[key] != nil { return true }

        guard let data = bookmarks()[key] else { return false }

        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            forget(key)
            return false
        }

        guard resolved.startAccessingSecurityScopedResource() else {
            forget(key)
            return false
        }

        active[key] = resolved

        // A stale bookmark still resolved, so the folder is reachable; refresh the
        // stored data while access is open rather than asking the viewer again.
        if isStale, let refreshed = makeBookmark(resolved) {
            store(refreshed, for: key)
        }

        return true
    }

    /// Asks the viewer to point at the folder, then remembers the grant.
    ///
    /// - Returns: true when access was granted.
    static func requestAccess(toFolderOf videoURL: URL) -> Bool {
        let folder = videoURL.deletingLastPathComponent().standardizedFileURL

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.message = String(
            format: L10n.string("subtitle.folder_access.panel_message"),
            folder.lastPathComponent
        )
        panel.prompt = L10n.string("subtitle.folder_access.panel_prompt")

        guard panel.runModal() == .OK, let chosen = panel.url else { return false }

        // The viewer can navigate elsewhere in the panel. A grant for some other folder
        // does not help this film, and silently accepting it would leave them wondering
        // why nothing changed.
        guard chosen.standardizedFileURL.path == folder.path else { return false }

        guard let data = makeBookmark(chosen) else { return false }
        store(data, for: folder.path)

        return restoreAccess(toFolderOf: videoURL)
    }

    /// Whether the viewer has already been asked about this folder and said yes.
    static func hasAccess(toFolderOf videoURL: URL) -> Bool {
        let key = videoURL.deletingLastPathComponent().standardizedFileURL.path
        return active[key] != nil || bookmarks()[key] != nil
    }

    private static func makeBookmark(_ url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func bookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    private static func store(_ data: Data, for key: String) {
        var all = bookmarks()
        all[key] = data
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }

    private static func forget(_ key: String) {
        var all = bookmarks()
        guard all.removeValue(forKey: key) != nil else { return }
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }
}
