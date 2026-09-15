import Foundation
import GlazeBooks
import GlazeCore

/// A file another app handed to Glaze.
///
/// Declaring the document types is only half of it. "Copy to Glaze" drops the file
/// into `Documents/Inbox`, and opening one in place hands over a security-scoped URL
/// somewhere else entirely — neither is where the library looks. Without this, Glaze
/// would appear in the share sheet and then appear to do nothing, which is worse than
/// not appearing at all.
@MainActor
enum IOSIncomingFile {
    /// - Returns: true when a file landed in the device folder.
    @discardableResult
    static func receive(_ url: URL) -> Bool {
        let root = IOSLibraryModel.deviceLibraryURL
        let fileManager = FileManager.default

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard fileManager.fileExists(atPath: url.path) else { return false }

        // Shared files used to land at the top of the folder in a heap. Sorting them
        // into the shelf folders is where those folders earn their keep — and it is
        // only a tidier resting place, not what decides which shelf shows the file.
        let shelf: IOSDeviceFolder.Shelf? = MediaFileTypes.isVideo(url)
            ? .films
            : (BookFileTypes.isBook(url) ? .books : nil)
        let home = shelf.flatMap { IOSDeviceFolder.folder(for: $0, creating: true) } ?? root
        let destination = unique(home.appendingPathComponent(url.lastPathComponent))

        // Already ours — the system put it in `Inbox` for us, so move it up rather
        // than copying and leaving a second copy behind.
        let inOurFolder = url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path)
        do {
            if inOurFolder {
                guard url.standardizedFileURL != destination.standardizedFileURL else { return true }
                try fileManager.moveItem(at: url, to: destination)
            } else {
                try fileManager.copyItem(at: url, to: destination)
            }
        } catch {
            return false
        }

        // The inbox is the system's staging area, not a place to keep anything.
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        if let leftovers = try? fileManager.contentsOfDirectory(atPath: inbox.path), leftovers.isEmpty {
            try? fileManager.removeItem(at: inbox)
        }
        return true
    }

    private static func unique(_ candidate: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let name = candidate.lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        var index = 2
        var next = candidate
        repeat {
            let attempt = suffix.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(suffix)"
            next = candidate.deletingLastPathComponent().appendingPathComponent(attempt)
            index += 1
        } while fileManager.fileExists(atPath: next.path)
        return next
    }
}
