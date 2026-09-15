import Foundation

/// One folder, and the files directly inside it.
public struct LocalFolderScan: Sendable {
    public let folder: URL
    public let files: [URL]

    public init(folder: URL, files: [URL]) {
        self.folder = folder
        self.files = files
    }

    public var fileNames: [String] { files.map(\.lastPathComponent) }
}

/// Walks a folder on the device, bounded.
///
/// Shared because two very different readers want the same walk: the film library
/// and the bookshelf. They live in different modules — a television has no use for
/// the bookshelf — so the traversal is here rather than duplicated in both, where it
/// would quietly drift apart.
public struct LocalFolderWalker {
    public struct Limits: Sendable {
        /// How far below the folder to walk. People do keep `Films/Title/file.mkv`.
        public var depth: Int
        /// A ceiling on how many folders one walk will open.
        public var folders: Int

        public init(depth: Int = 5, folders: Int = 800) {
            self.depth = depth
            self.folders = folders
        }
    }

    private let limits: Limits
    private let fileManager: FileManager

    public init(limits: Limits = Limits(), fileManager: FileManager = .default) {
        self.limits = limits
        self.fileManager = fileManager
    }

    /// Not `Sendable`: it holds a `FileManager`, and nothing needs to carry one
    /// across actors — the two loaders each make their own inside their own actor.
    ///
    /// - Parameter onProgress: called with folders read so far.
    public func walk(root: URL, onProgress: ((Int) -> Void)? = nil) -> [LocalFolderScan] {
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        var visited: Set<String> = []
        var scans: [LocalFolderScan] = []

        while !queue.isEmpty, scans.count < limits.folders {
            let (folder, depth) = queue.removeFirst()
            guard visited.insert(folder.standardizedFileURL.path).inserted else { continue }

            let children = contents(of: folder)
            scans.append(LocalFolderScan(folder: folder, files: children.files))
            onProgress?(scans.count)

            if depth < limits.depth {
                queue.append(contentsOf: children.directories.map { ($0, depth + 1) })
            }
        }
        return scans
    }

    /// Names a file by where it sits inside the folder, not by its full path.
    ///
    /// An app's Documents folder is under a container id that iOS is free to change,
    /// and an absolute path put that id inside every remembered page and every
    /// favourite. Reinstalling the app then lost the lot.
    public static func identifier(for file: URL, root: URL) -> String {
        let path = file.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        guard path.hasPrefix(base) else { return path }
        return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func contents(of folder: URL) -> (directories: [URL], files: [URL]) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], []) }

        var directories: [URL] = []
        var files: [URL] = []
        for entry in entries where !Self.isSkipped(entry) {
            if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                directories.append(entry)
            } else {
                files.append(entry)
            }
        }
        return (directories, files)
    }

    /// AppleDouble files travel with anything copied from a Mac and are not content.
    private static func isSkipped(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasPrefix(".") || name.hasPrefix("._") || skippedNames.contains(name)
    }

    private static let skippedNames: Set<String> = [
        ".ds_store", "__macosx", "thumbs.db", "desktop.ini"
    ]
}
