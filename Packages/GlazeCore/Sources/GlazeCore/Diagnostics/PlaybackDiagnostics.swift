import Foundation

/// Observes snapshots pushed by the player; never calls the playback engine from
/// its timer. Old callbacks can be distinguished by a separate session UUID.
public final class PlaybackDiagnostics: @unchecked Sendable {
    public let id = UUID().uuidString
    private let queue = DispatchQueue(label: "com.glaze.playback-diagnostics")
    private var timer: DispatchSourceTimer?
    private var expectingProgress = true
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var lastTime: Double = -1
    private var reported = false

    public init(url: URL) {
        DiagnosticsCenter.shared.record("playback.start", id: id)
        DiagnosticsCenter.shared.record("playback.resource", id: DiagnosticsCenter.shared.token(for: url.absoluteString))
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 5, repeating: 5)
        source.setEventHandler { [weak self] in self?.check() }
        timer = source
        source.resume()
    }

    public func progress(time: Double, playing: Bool) {
        queue.async { [self] in
            if time != lastTime {
                if reported { DiagnosticsCenter.shared.record("playback.recovered", id: id) }
                lastProgress = ProcessInfo.processInfo.systemUptime
                reported = false
                lastTime = time
            }
            expectingProgress = playing
        }
    }

    public func expectProgress(_ value: Bool) {
        queue.async { [self] in
            expectingProgress = value
            lastProgress = ProcessInfo.processInfo.systemUptime
            reported = false
        }
    }

    private func check() {
        guard DiagnosticsCenter.shared.isActive else {
            lastProgress = ProcessInfo.processInfo.systemUptime
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastProgress
        if expectingProgress, elapsed >= 15, !reported {
            reported = true
            DiagnosticsCenter.shared.record("playback.stalled", id: id, numbers: ["seconds": elapsed])
        }
    }

    deinit {
        timer?.cancel()
        DiagnosticsCenter.shared.record("playback.session_end", id: id)
    }
}
