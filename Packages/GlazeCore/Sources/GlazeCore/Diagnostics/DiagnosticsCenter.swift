import Foundation
import CryptoKit
import OSLog
import Network

/// Only static event names and numeric fields cross this boundary. Never pass error
/// descriptions, filenames, URLs, headers or subtitle text to a diagnostic event.
public final class DiagnosticsCenter: @unchecked Sendable {
    public static let shared = DiagnosticsCenter()
    private let queue = DispatchQueue(label: "com.glaze.diagnostics", qos: .utility)
    private let directory: URL
    private let defaults: UserDefaults
    private let salt: SymmetricKey
    private let logger = Logger(subsystem: "com.edwin.glaze", category: "diagnostics")
    private var timer: DispatchSourceTimer?
    private let networkMonitor = NWPathMonitor()
    private var heartbeatPending = false
    private var heartbeatAt = ProcessInfo.processInfo.systemUptime
    private var reportedHang = false
    private var active = true
    private var enabled: Bool
    private let maximumBytes: Int
    private let started = ProcessInfo.processInfo.systemUptime
    private let retention: TimeInterval = 7 * 86_400
    private static let preference = "diagnostics.enabled"

    public init(directory: URL? = nil, defaults: UserDefaults = .standard, maximumBytes: Int = 5_000_000) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glaze/Diagnostics", isDirectory: true)
        self.defaults = defaults
        self.maximumBytes = maximumBytes
        enabled = defaults.bool(forKey: Self.preference)
        if let data = defaults.data(forKey: "diagnostics.salt") {
            salt = SymmetricKey(data: data)
        } else {
            let key = SymmetricKey(size: .bits256)
            salt = key
            defaults.set(key.withUnsafeBytes { Data($0) }, forKey: "diagnostics.salt")
        }
    }

    public var isEnabled: Bool { queue.sync { enabled } }
    public var isActive: Bool { queue.sync { active } }

    public func setEnabled(_ value: Bool) {
        queue.sync {
            enabled = value
            defaults.set(value, forKey: Self.preference)
        }
        record("diagnostics.enabled", numbers: ["enabled": value ? 1 : 0])
    }

    /// HMAC uses an installation-local random key. The input is never persisted.
    public func token(for value: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: salt)
            .prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    public func record(_ event: StaticString, id: String? = nil, numbers: [String: Double] = [:]) {
        // Non-finite values cannot be encoded as JSON. Keys are fixed by call sites.
        let values = numbers.filter { $0.value.isFinite }
        let name = String(describing: event)
        let safeID = id.flatMap { value -> String? in
            guard [24, 36].contains(value.count), value.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
            return value
        }
        queue.async { [self] in
            guard enabled else { return }
            write(name, id: safeID, numbers: values)
        }
    }

    public func start() {
        record("app.launch", numbers: ["schema": 1])
        queue.async { [self] in
            guard timer == nil else { return }
            networkMonitor.pathUpdateHandler = { [weak self] path in
                self?.record("network.path", numbers: ["reachable": path.status == .satisfied ? 1 : 0,
                    "expensive": path.isExpensive ? 1 : 0, "constrained": path.isConstrained ? 1 : 0])
            }
            networkMonitor.start(queue: queue)
            prune()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 2, repeating: 2)
            source.setEventHandler { [weak self] in self?.checkHeartbeat() }
            timer = source
            source.resume()
        }
    }

    public func setActive(_ value: Bool) {
        record("app.activity", numbers: ["active": value ? 1 : 0])
        queue.async { [self] in
            active = value
            heartbeatPending = false
            reportedHang = false
        }
    }

    /// Runs independently of the main queue. It never calls VLC or any UI getter,
    /// which may be the very call that has deadlocked the main thread.
    private func checkHeartbeat() {
        guard enabled, active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if heartbeatPending {
            if now - heartbeatAt >= 10, !reportedHang {
                write("app.main_unresponsive", id: nil, numbers: ["seconds": now - heartbeatAt])
                reportedHang = true
            }
            return
        }
        heartbeatPending = true
        heartbeatAt = now
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queue.async { [self] in
                if reportedHang {
                    write("app.main_recovered", id: nil, numbers: ["seconds": ProcessInfo.processInfo.systemUptime - heartbeatAt])
                }
                heartbeatPending = false
                reportedHang = false
            }
        }
    }

    private func write(_ event: String, id: String?, numbers: [String: Double]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? folder.setResourceValues(resourceValues)
            var object: [String: Any] = ["event": event, "timestamp": Date().timeIntervalSince1970,
                                        "elapsed": ProcessInfo.processInfo.systemUptime - started, "values": numbers]
            // IDs are generated UUIDs or HMACs at call sites; no raw resource identity.
            if let id { object["id"] = id }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
            let current = directory.appendingPathComponent("events-0.jsonl")
            if let created = try? current.resourceValues(forKeys: [.creationDateKey]).creationDate,
               Date().timeIntervalSince(created) > 86_400 { rotate() }
            let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size + data.count > maximumBytes { rotate() }
            if !FileManager.default.fileExists(atPath: current.path) {
                FileManager.default.createFile(atPath: current.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: current)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            logger.info("\(event, privacy: .public)")
        } catch {
            logger.error("Diagnostic write failed")
        }
    }

    private func rotate() {
        let fm = FileManager.default
        for index in stride(from: 2, through: 1, by: -1) {
            let target = directory.appendingPathComponent("events-\(index).jsonl")
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: directory.appendingPathComponent("events-\(index - 1).jsonl"), to: target)
        }
    }

    private func prune() {
        for index in 0...2 {
            let url = directory.appendingPathComponent("events-\(index).jsonl")
            if let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
               Date().timeIntervalSince(date) > retention { try? FileManager.default.removeItem(at: url) }
        }
    }

    public func export() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    prune()
                    var data = Data()
                    let metadata: [String: Any] = ["event": "report.metadata", "schema": 1,
                        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                        "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                        "os": ProcessInfo.processInfo.operatingSystemVersionString]
                    data.append(try JSONSerialization.data(withJSONObject: metadata))
                    data.append(10)
                    for index in stride(from: 2, through: 0, by: -1) {
                        if let part = try? Data(contentsOf: directory.appendingPathComponent("events-\(index).jsonl")) { data.append(part) }
                    }
                    let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GlazeDiagnostics", isDirectory: true)
                    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
                    let url = exportDirectory.appendingPathComponent("glaze-diagnostics.jsonl")
                    try data.write(to: url, options: .atomic)
                    continuation.resume(returning: url)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func clear() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                for index in 0...2 { try? FileManager.default.removeItem(at: directory.appendingPathComponent("events-\(index).jsonl")) }
                try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("GlazeDiagnostics/glaze-diagnostics.jsonl"))
                continuation.resume()
            }
        }
    }
}

/// Records operation duration even across thrown errors. A begin without an end is
/// useful after a process is killed. Call succeed only after the operation finishes.
public final class DiagnosticOperation: @unchecked Sendable {
    private let id = UUID().uuidString
    private let started = ProcessInfo.processInfo.systemUptime
    private let center: DiagnosticsCenter
    private var succeeded = false
    public init(_ event: StaticString, center: DiagnosticsCenter = .shared) {
        self.center = center
        center.record(event, id: id)
    }
    public func succeed() { succeeded = true }
    deinit {
        center.record("operation.end", id: id, numbers: ["success": succeeded ? 1 : 0,
            "milliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1000])
    }
}
