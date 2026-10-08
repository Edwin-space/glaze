import Foundation

/// A line-by-line record of what the player did, written into the app's own folder.
///
/// Reaching for this was a last resort and should have been a first one. Three
/// explanations for a film that would not open were argued from reading the code —
/// a resume seek blocking the main thread was the most convincing of them — and each
/// was wrong. A player that will not say what it is doing can only be guessed at.
///
/// Off unless asked for, so nothing is written during ordinary use:
///
///     app.launchArguments += ["-glaze.playbackLog", "YES"]
///
/// and afterwards:
///
///     xcrun devicectl device copy from --domain-type appDataContainer \
///       --domain-identifier com.edwin.glaze --source Documents/glaze-playback.log ...
enum PlaybackLog {
    static let isEnabled = UserDefaults.standard.bool(forKey: "glaze.playbackLog")

    private static let queue = DispatchQueue(label: "glaze.playbackLog")
    private static let started = Date()

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("glaze-playback.log")
    }

    static func begin(_ note: String) {
        guard isEnabled, let fileURL else { return }
        queue.async { try? "\n===== \(note) =====\n".data(using: .utf8)?.append(to: fileURL) }
    }

    static func write(_ note: @autoclosure () -> String) {
        guard isEnabled, let fileURL else { return }
        let line = String(format: "%7.2f  %@\n", Date().timeIntervalSince(started), note())
        queue.async { try? line.data(using: .utf8)?.append(to: fileURL) }
    }
}

private extension Data {
    func append(to url: URL) throws {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: self)
        } else {
            try write(to: url, options: .atomic)
        }
    }
}
