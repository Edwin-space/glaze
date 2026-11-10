import Foundation
import GlazeCore
import Observation

/// One timed-text renderer for cached SRTs. A seek recomputes the active cue from
/// the clock instead of waiting for VLC to encounter the next subtitle packet.
@MainActor
@Observable
final class IOSSidecarSubtitles {
    private(set) var text = ""
    private(set) var isPreparing = false
    private(set) var failed = false
    private(set) var selectedID: String?
    private(set) var tracks: [IOSTrackOption] = []
    var onSelectionChanged: (() -> Void)?

    @ObservationIgnored private let loader = PlaybackSubtitleLoader()
    @ObservationIgnored private var prepared: [String: PreparedPlaybackSubtitle] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var lastIndices: [Int] = []

    func load(_ resource: NetworkSubtitleResource, sessionID: String?) {
        cancelPreparation()
        let token = revision
        self.sessionID = sessionID
        isPreparing = true
        failed = false
        DiagnosticsCenter.shared.record("subtitle.prepare_begin", id: sessionID,
            numbers: ["remote": resource.url.isFileURL ? 0 : 1])
        let started = ProcessInfo.processInfo.systemUptime
        task = Task { [weak self, loader] in
            do {
                let result = try await loader.prepare(resource)
                guard let self, revision == token, !Task.isCancelled else { return }
                let id = "sidecar:" + DiagnosticsCenter.shared.token(for: resource.url.absoluteString)
                prepared[id] = result
                if !tracks.contains(where: { $0.id == id }) {
                    // Bound per-film parsing memory as well as the disk cache.
                    if tracks.count >= 4, let old = tracks.first(where: { $0.id != selectedID }) {
                        tracks.removeAll { $0.id == old.id }
                        prepared.removeValue(forKey: old.id)
                    }
                    let language = resource.languageCode ?? SubtitleFile.manual(
                        url: URL(fileURLWithPath: resource.displayName)).languageCode
                    tracks.append(IOSTrackOption(id: id,
                        title: language.flatMap { L10n.languageName(for: $0) } ?? resource.displayName,
                        languageCode: language, isSelected: false))
                }
                isPreparing = false
                task = nil
                select(id: id)
                DiagnosticsCenter.shared.record("subtitle.prepare_ready", id: sessionID, numbers: [
                    "milliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1000,
                    "cues": Double(result.timeline.cues.count)])
            } catch {
                guard let self, revision == token, !Task.isCancelled else { return }
                isPreparing = false
                failed = true
                task = nil
                DiagnosticsCenter.shared.record("subtitle.prepare_failed", id: sessionID,
                    numbers: Self.failureFields(error).merging([
                        "milliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1000
                    ], uniquingKeysWith: { _, new in new }))
                onSelectionChanged?()
            }
        }
    }

    @discardableResult
    func select(id: String) -> Bool {
        guard prepared[id] != nil else { return false }
        cancelPreparation()
        selectedID = id
        failed = false
        lastIndices = []
        refreshSelection()
        onSelectionChanged?()
        return true
    }

    func deselect() {
        cancelPreparation()
        selectedID = nil
        failed = false
        text = ""
        lastIndices = []
        refreshSelection()
    }

    func reset() {
        deselect()
        prepared = [:]
        tracks = []
        sessionID = nil
        failed = false
    }

    func suppressDuringSeek() { text = "" }

    func update(at time: TimeInterval, delay: TimeInterval, sequence: Int = 0, force: Bool = false) {
        guard let selectedID, let timeline = prepared[selectedID]?.timeline else { return }
        let indices = timeline.activeIndices(at: time - delay)
        if force || indices != lastIndices {
            text = indices.map { timeline.cues[$0].text }.joined(separator: "\n")
            lastIndices = indices
            DiagnosticsCenter.shared.record(force ? "subtitle.resync" : "subtitle.cue_changed", id: sessionID,
                numbers: ["seconds": time, "sequence": Double(sequence),
                          "active": indices.isEmpty ? 0 : 1, "cue_index": Double(indices.first ?? -1),
                          "cue_count": Double(indices.count)])
        }
    }

    private func cancelPreparation() {
        revision = UUID()
        task?.cancel()
        task = nil
        isPreparing = false
    }

    private func refreshSelection() {
        tracks = tracks.map {
            IOSTrackOption(id: $0.id, title: $0.title, languageCode: $0.languageCode, isSelected: $0.id == selectedID)
        }
    }

    private static func failureFields(_ error: Error) -> [String: Double] {
        if let error = error as? URLError { return ["category": 1, "code": Double(error.code.rawValue)] }
        if let error = error as? NetworkSubtitleLoader.LoaderError {
            switch error {
            case .httpStatus(let status): return ["category": 2, "code": Double(status)]
            case .invalidResponse: return ["category": 2, "code": 0]
            case .responseTooLarge: return ["category": 2, "code": 1]
            case .conversionUnavailable: return ["category": 2, "code": 2]
            }
        }
        if let error = error as? SubtitleParser.ParseError {
            switch error {
            case .unsupportedFormat: return ["category": 3, "code": 1]
            case .unreadableFile: return ["category": 3, "code": 2]
            case .emptySubtitle: return ["category": 3, "code": 3]
            }
        }
        return ["category": 0, "code": Double((error as NSError).code)]
    }

    #if DEBUG
    func auditActiveCueCount(at time: TimeInterval, delay: TimeInterval) -> Int {
        guard let selectedID, let timeline = prepared[selectedID]?.timeline else { return 0 }
        return timeline.activeIndices(at: time - delay).count
    }

    /// Numeric test telemetry only, deliberately excluding caption text or URLs.
    func auditTargets(endingBefore duration: TimeInterval) -> [TimeInterval] {
        guard let selectedID, let cues = prepared[selectedID]?.timeline.cues, !cues.isEmpty else { return [] }
        let playable = cues.filter { $0.startTime >= 0 && $0.startTime + 0.4 < duration }
        guard !playable.isEmpty else { return [] }
        return [0.2, 0.5, 0.8].map { fraction in
            let cue = playable[min(Int(Double(playable.count) * fraction), playable.count - 1)]
            return cue.startTime + min((cue.endTime - cue.startTime) / 2, 0.4)
        }
    }
    #endif
}
