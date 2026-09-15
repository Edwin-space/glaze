import Foundation

/// Whether a film has been watched, as a list wants to show it.
public enum WatchState: Equatable, Sendable {
    /// Never started — worth marking, because in a folder of forty episodes it is the
    /// one thing a person is looking for.
    case new
    /// Started and left, with how far through: 0…1.
    case inProgress(Double)
    case watched
}

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
    /// How long each part-watched film is, so a list can say how far through it is.
    /// Kept apart from `key` so the positions stay in the shape the Mac and the
    /// television already read.
    private let durationsKey = "playback.durations"
    /// Films watched to the end.
    ///
    /// Needed because finishing a film deliberately *forgets* its position — replaying
    /// it should start from the top — and with only positions to go on, "watched" and
    /// "never played" were the same empty entry. No list could tell them apart.
    private let watchedKey = "playback.watched"

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
    /// so replaying it starts from the beginning — and is remembered as watched.
    public func record(_ time: TimeInterval, duration: TimeInterval, for resource: MediaResource) {
        let identifier = Self.identifier(for: resource)
        var all = positions()
        var durations = storedDurations()

        let isFinished = duration > 0 && time / duration >= Self.watchedThreshold
        if isFinished {
            var watched = watchedSet()
            if watched.insert(identifier).inserted {
                defaults.set(Array(watched), forKey: watchedKey)
            }
        }

        if isFinished || time < Self.minimumResumeSeconds {
            guard all[identifier] != nil else { return }
            all[identifier] = nil
            durations[identifier] = nil
        } else {
            all[identifier] = time
            if duration > 0 { durations[identifier] = duration }
        }

        defaults.set(all, forKey: key)
        defaults.set(durations, forKey: durationsKey)
    }

    /// What a list should show for this film.
    ///
    /// A film being watched again reads as in progress rather than watched: the
    /// question someone has while it is half done is where they got to.
    public func state(for resource: MediaResource) -> WatchState {
        let identifier = Self.identifier(for: resource)
        if let time = positions()[identifier], time >= Self.minimumResumeSeconds {
            guard let duration = storedDurations()[identifier], duration > 0 else {
                return .inProgress(0)
            }
            return .inProgress(min(max(time / duration, 0), 1))
        }
        return watchedSet().contains(identifier) ? .watched : .new
    }

    /// Takes a film back to unwatched — for someone who watched it on another device,
    /// or wants it to read as new again.
    public func markUnwatched(_ resource: MediaResource) {
        let identifier = Self.identifier(for: resource)
        var watched = watchedSet()
        if watched.remove(identifier) != nil {
            defaults.set(Array(watched), forKey: watchedKey)
        }
        forget(resource)
    }

    public func markWatched(_ resource: MediaResource) {
        let identifier = Self.identifier(for: resource)
        var watched = watchedSet()
        if watched.insert(identifier).inserted {
            defaults.set(Array(watched), forKey: watchedKey)
        }
        forget(resource)
    }

    public func forget(_ resource: MediaResource) {
        let identifier = Self.identifier(for: resource)
        var durations = storedDurations()
        if durations.removeValue(forKey: identifier) != nil {
            defaults.set(durations, forKey: durationsKey)
        }
        var all = positions()
        guard all.removeValue(forKey: identifier) != nil else { return }
        defaults.set(all, forKey: key)
    }

    private func positions() -> [String: TimeInterval] {
        defaults.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
    }

    private func storedDurations() -> [String: TimeInterval] {
        defaults.dictionary(forKey: durationsKey) as? [String: TimeInterval] ?? [:]
    }

    private func watchedSet() -> Set<String> {
        Set(defaults.stringArray(forKey: watchedKey) ?? [])
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
