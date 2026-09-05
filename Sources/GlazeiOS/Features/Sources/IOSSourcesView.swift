import GlazeCore
import SwiftUI

/// Where the films come from: servers found on the network, and NAS addresses typed in.
struct IOSSourcesView: View {
    let discovery: NetworkMediaBrowserModel
    let connections: WebDAVConnectionStore
    let onUseDLNA: (NetworkMediaServer) -> Void
    let onUseWebDAV: (WebDAVConnection) -> Void

    @State private var isAdding = false

    var body: some View {
        List {
            Section(L10n.string("settings.network.discovery.title")) {
                if discovery.servers.isEmpty {
                    Label(
                        discovery.phase == .discovering
                            ? L10n.string("network.browser.discovering")
                            : L10n.string("network.browser.empty"),
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .foregroundStyle(IOSTheme.dim)
                } else {
                    ForEach(discovery.servers) { server in
                        Button { onUseDLNA(server) } label: {
                            Label(server.friendlyName, systemImage: "play.tv")
                        }
                    }
                }
            }

            Section(L10n.string("webdav.section.title")) {
                ForEach(connections.connections) { connection in
                    Button { onUseWebDAV(connection) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.name)
                            Text(connection.rootURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(IOSTheme.dim)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { connections.remove(connections.connections[index]) }
                }

                Button {
                    isAdding = true
                } label: {
                    Label(L10n.string("webdav.add"), systemImage: "plus")
                }
            }
        }
        .navigationTitle(L10n.string("tv.navigation.sources"))
        .task { await discovery.discoverIfNeeded() }
        .refreshable { await discovery.discover() }
        .sheet(isPresented: $isAdding) {
            IOSWebDAVSetupView { connection, password in
                connections.save(connection, password: password)
                onUseWebDAV(connection)
            }
        }
    }
}

/// Typing a NAS address on a phone, which is the one place people will actually do it
/// rather than on a television remote.
struct IOSWebDAVSetupView: View {
    let onSave: (WebDAVConnection, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("webdav.field.name"), text: $name)
                    TextField(L10n.string("webdav.field.url"), text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField(L10n.string("webdav.field.username"), text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(L10n.string("webdav.field.password"), text: $password)
                } footer: {
                    Text(L10n.string("webdav.field.url.hint"))
                }
            }
            .navigationTitle(L10n.string("webdav.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("webdav.connect")) { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: address)?.host != nil
    }

    private func save() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)) else { return }
        onSave(
            WebDAVConnection(name: name, rootURL: url, username: username),
            password.isEmpty ? nil : password
        )
        dismiss()
    }
}
