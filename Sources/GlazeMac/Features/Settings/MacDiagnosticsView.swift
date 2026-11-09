import GlazeCore
import SwiftUI

struct MacDiagnosticsView: View {
    @State private var enabled = DiagnosticsCenter.shared.isEnabled
    @State private var report: URL?
    @State private var failed = false
    var body: some View {
        Form {
            Toggle(L10n.string("diagnostics.enabled"), isOn: $enabled)
                .onChange(of: enabled) { _, value in DiagnosticsCenter.shared.setEnabled(value) }
            Text(L10n.string("diagnostics.detail"))
            Button(L10n.string("diagnostics.prepare")) {
                Task {
                    do { report = try await DiagnosticsCenter.shared.export(); failed = false }
                    catch { failed = true }
                }
            }
            if let report { ShareLink(L10n.string("diagnostics.export"), item: report) }
            if failed { Text(L10n.string("diagnostics.failed")) }
            Button(L10n.string("diagnostics.clear"), role: .destructive) {
                Task { await DiagnosticsCenter.shared.clear(); report = nil }
            }
            Text(L10n.string("diagnostics.instructions"))
        }.padding()
    }
}
