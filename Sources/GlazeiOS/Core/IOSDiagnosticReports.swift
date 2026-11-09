import GlazeCore
import MetricKit

/// MetricKit payloads contain more than this product needs. Persist numeric summaries
/// only, never the raw JSON or system metadata. Full symbolicated crashes remain in
/// Xcode/TestFlight, associated with the archived build's dSYM.
final class IOSDiagnosticReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = IOSDiagnosticReports()
    func start() { MXMetricManager.shared.add(self) }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            DiagnosticsCenter.shared.record("system.diagnostics", numbers: [
                "crashes": Double(payload.crashDiagnostics?.count ?? 0),
                "hangs": Double(payload.hangDiagnostics?.count ?? 0),
                "cpu": Double(payload.cpuExceptionDiagnostics?.count ?? 0),
                "disk": Double(payload.diskWriteExceptionDiagnostics?.count ?? 0)
            ])
        }
    }
}
