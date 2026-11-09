import GlazeCore
import SwiftUI

struct MacDiagnosticsView: View {
    @State private var enabled = DiagnosticsCenter.shared.isEnabled
    @State private var report: URL?
    @State private var failed = false
    @State private var isPreparing = false
    var body: some View {
        SettingsPage(titleKey: "diagnostics.title", descriptionKey: "diagnostics.detail") {
            SettingsCard(titleKey: "diagnostics.section.recording") {
                Toggle(L10n.string("diagnostics.enabled"), isOn: $enabled)
                    .onChange(of: enabled) { _, value in DiagnosticsCenter.shared.setEnabled(value) }
            }
            SettingsCard(titleKey: "diagnostics.section.report") {
                Text(L10n.string("diagnostics.instructions"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.string("diagnostics.prepare")) {
                    guard !isPreparing else { return }
                    isPreparing = true
                    failed = false
                    report = nil
                    Task {
                        defer { isPreparing = false }
                        do { report = try await DiagnosticsCenter.shared.export() }
                        catch { failed = true }
                    }
                }
                .disabled(isPreparing)
                if isPreparing {
                    ProgressView(L10n.string("diagnostics.preparing"))
                        .controlSize(.small)
                }
                if let report { ShareLink(L10n.string("diagnostics.export"), item: report) }
                if failed { Text(L10n.string("diagnostics.failed")).foregroundStyle(.red) }
            }
            SettingsCard(titleKey: "diagnostics.section.data") {
                Button(L10n.string("diagnostics.clear"), role: .destructive) {
                    Task { await DiagnosticsCenter.shared.clear(); report = nil; failed = false }
                }
                .disabled(isPreparing)
            }
        }
    }
}
