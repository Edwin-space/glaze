import GlazeCore
import SwiftUI

struct IOSDiagnosticsView: View {
    @State private var enabled = DiagnosticsCenter.shared.isEnabled
    @State private var reportURL: URL?
    @State private var busy = false
    @State private var failed = false
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                Toggle(L10n.string("diagnostics.enabled"), isOn: $enabled)
                    .onChange(of: enabled) { _, value in DiagnosticsCenter.shared.setEnabled(value) }
            } footer: { Text(L10n.string("diagnostics.detail")) }
            Section {
                Button(L10n.string("diagnostics.prepare")) {
                    busy = true
                    failed = false
                    Task {
                        do { reportURL = try await DiagnosticsCenter.shared.export() }
                        catch { failed = true }
                        busy = false
                    }
                }.disabled(busy)
                if busy { ProgressView() }
                if let reportURL { ShareLink(L10n.string("diagnostics.export"), item: reportURL) }
                if failed { Text(L10n.string("diagnostics.failed")).foregroundStyle(.red) }
                Button(L10n.string("diagnostics.clear"), role: .destructive) { confirmClear = true }
            } footer: { Text(L10n.string("diagnostics.instructions")) }
        }
        .navigationTitle(L10n.string("diagnostics.title"))
        .confirmationDialog(L10n.string("diagnostics.clear"), isPresented: $confirmClear) {
            Button(L10n.string("diagnostics.clear"), role: .destructive) {
                Task { await DiagnosticsCenter.shared.clear(); reportURL = nil }
            }
        }
    }
}
