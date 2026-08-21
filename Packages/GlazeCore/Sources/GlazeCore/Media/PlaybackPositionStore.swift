import Foundation

/// Remembers where each video was left off.
///
/// Keyed on `MediaResource` rather than a path so a video streamed from a NAS resumes
/// the same way a local file does.
/// Not `Sendable`: it holds a `UserDefaults`, and nothing needs to carry it across
/// actors — callers use it from the main actor.
public struct PlaybackPositionStore {
    /// Below this, there is nothing worth resuming — the viewer had barely started.
    public static let minimumResumeSeconds: TimeInterval = 10
    /// Past this fraction the video counts as watched, and resuming would drop the
    /// viewer onto the closing seconds instead of starting the next one cleanly.
    public static let watchedThreshold = 0.97

    private let defaults: UserDefaults
    private let key = "playback.positions"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// - Returns: the time to resume from, or nil when the video should start over.
    public func position(for resource: MediaResource) -> TimeInterval? {
        let stored = positions()[Self.identifier(for: resource)]
        guard let stored, stored >= Self.minimumResumeSeconds else { return nil }
        return stored
    }

    /// Records progress. A video watched to the end is forgotten rather than stored,
    /// so replaying it starts from the beginning.
    public func record(_ time: TimeInterval, duration: TimeInterval, for resource: MediaResource) {
        let identifier = Self.identifier(for: resource)
        var all = positions()

        let isFinished = duration > 0 && time / duration >= Self.watchedThreshold
        if isFinished || time < Self.minimumResumeSeconds {
            guard all[identifier] != nil else { return }
            all[identifier] = nil
        } else {
            all[identifier] = time
        }

        defaults.set(all, forKey: key)
    }

    public func forget(_ resource: MediaResource) {
        var all = positions()
        guard all.removeValue(forKey: Self.identifier(for: resource)) != nil else { return }
        defaults.set(all, forKey: key)
    }

    private func positions() -> [String: TimeInterval] {
        defaults.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
    }

    /// Local files are keyed by path; a streamed resource has none, so its
    /// server-scoped object id stands in.
    static func identifier(for resource: MediaResource) -> String {
        switch resource {
        case .localFile(let url):
            url.standardizedFileURL.path
        case .network(let networkResource):
            "\(networkResource.serverID)#\(networkResource.objectID)"
        }
    }
}
