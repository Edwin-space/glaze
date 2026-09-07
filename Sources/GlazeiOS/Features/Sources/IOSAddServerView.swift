import GlazeCore
import SwiftUI

/// Choosing what kind of server to add, before being asked for anything about it.
///
/// Every file app on this platform opens with this list, because "what do you have?"
/// is the question a person can answer. Asking for an address first only works if you
/// already know which of several addresses your NAS wants.
struct IOSAddServerView: View {
    let discovery: NetworkMediaBrowserModel
    let onChoose: (IOSServerKind) -> Void
    let onUseDLNA: (NetworkMediaServer) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(IOSServerKind.allCases) { kind in
                        Button {
                            dismiss()
                            onChoose(kind)
                        } label: {
                            IOSListRow(
                                symbol: kind.symbol,
                                title: kind.title,
                                detail: kind.detail
                            )
                        }
                    }
                }

                // What is already answering on this network, so nobody types an
                // address for a server that could just be tapped.
                Section {
                    if discovery.servers.isEmpty {
                        HStack(spacing: IOSTheme.Spacing.small) {
                            if discovery.phase == .discovering { ProgressView() }
                            Text(
                                discovery.phase == .discovering
                                    ? L10n.string("network.browser.discovering")
                                    : L10n.string("network.browser.empty")
                            )
                            .foregroundStyle(IOSTheme.dim)
                        }
                    } else {
                        ForEach(discovery.servers) { server in
                            Button {
                                dismiss()
                                onUseDLNA(server)
                            } label: {
                                Label(server.friendlyName, systemImage: "play.tv")
                            }
                        }
                    }
                } header: {
                    Text(L10n.string("ios.server.found"))
                } footer: {
                    Text(L10n.string("ios.server.found.detail"))
                }
            }
            .glazeListBackground()
            .navigationTitle(L10n.string("ios.server.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
            }
            .task { await discovery.discoverIfNeeded() }
            .refreshable { await discovery.discover() }
        }
    }

}
