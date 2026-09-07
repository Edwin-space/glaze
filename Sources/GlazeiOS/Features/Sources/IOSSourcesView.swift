import GlazeCore
import SwiftUI

/// Where the films come from.
///
/// Laid out the way every file app on this platform lays it out: what is on the
/// device, then the servers that have been added, each saying what it speaks. Adding
/// one starts by choosing the kind, because "what do you have?" is a question a
/// person can answer — "what is the address?" is not, until you know which of your
/// NAS's several addresses it wants.
struct IOSSourcesView: View {
    let discovery: NetworkMediaBrowserModel
    let connections: WebDAVConnectionStore
    let synologyConnections: SynologyConnectionStore
    let library: IOSLibraryModel

    let onUseDevice: () -> Void
    let onUseDLNA: (NetworkMediaServer) -> Void
    let onUseWebDAV: (WebDAVConnection) -> Void
    let onUseSynology: (SynologyConnection) -> Void
    let onConnectedSynology: (SynologyConnection, String, SynologySession, String) -> Void

    @State private var opening: IOSSavedServer.ID?
    @State private var isAddingServer = false
    @State private var addingKind: IOSServerKind?
    @State private var sendingToTV: IOSPairingRequest?

    private var servers: [IOSSavedServer] {
        let all = synologyConnections.connections.map(IOSSavedServer.synology)
            + connections.connections.map(IOSSavedServer.webDAV)
        return all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            deviceSection
            serverSection
            aboutSection
        }
        .glazeListBackground()
        .navigationTitle(L10n.string("tv.navigation.sources"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingServer = true
                } label: {
                    Label(L10n.string("ios.server.add"), systemImage: "plus")
                }
            }
        }
        .task { await discovery.discoverIfNeeded() }
        .refreshable { await discovery.discover() }
        .sheet(isPresented: $isAddingServer) {
            IOSAddServerView(
                discovery: discovery,
                onChoose: { kind in
                    // DLNA needs no details, so it is not a form.
                    guard kind != .dlna else { return }
                    addingKind = kind
                },
                onUseDLNA: onUseDLNA
            )
        }
        .sheet(item: $sendingToTV) { request in
            IOSPairingScannerView(payload: request.payload)
        }
        .sheet(item: $addingKind) { kind in
            switch kind {
            case .synology:
                IOSSynologySetupView(onConnected: onConnectedSynology)
            case .webDAV:
                IOSWebDAVSetupView { connection, password in
                    connections.save(connection, password: password)
                    onUseWebDAV(connection)
                }
            case .dlna:
                EmptyView()
            }
        }
    }

    /// Films kept on the phone. A server is not always reachable, and this is the
    /// one source that needs nothing but the phone.
    private var deviceSection: some View {
        Section {
            NavigationLink {
                IOSDeviceFilesView(library: library, onOpenLibrary: onUseDevice)
            } label: {
                Label(L10n.string("ios.device.title"), systemImage: "iphone")
            }
        } header: {
            Text(L10n.string("ios.sources.device"))
        } footer: {
            Text(L10n.string("ios.sources.device.hint"))
        }
    }

    private var serverSection: some View {
        Section {
            if servers.isEmpty {
                Text(L10n.string("ios.server.empty"))
                    .font(.footnote)
                    .foregroundStyle(IOSTheme.dim)
            }
            ForEach(servers, content: serverRow)
                .onDelete(perform: remove)
        } header: {
            Text(L10n.string("ios.server.section"))
        } footer: {
            failureNote
        }
    }

    // Kept as its own view rather than inline: the section had grown a row with an
    // overlay, a disabled state and a context menu inside a ForEach inside a Section
    // with a header and a footer, and SwiftUI fell over instantiating the type.
    private func serverRow(_ server: IOSSavedServer) -> some View {
        Button { open(server) } label: {
            // The protocol under the name, so two entries for the same box are told
            // apart at a glance.
            IOSListRow(
                symbol: server.kind.symbol,
                title: server.name,
                detail: "\(server.kind.title) · \(server.detail)"
            )
        }
        .disabled(opening != nil)
        .overlay(alignment: .trailing) {
            // Opening a NAS means signing in again, which takes a moment. The
            // feedback belongs here, not on the screen it moves to.
            if opening == server.id {
                ProgressView()
            }
        }
        .contextMenu {
            // Typing this again on a remote control is the worst job in the app;
            // the phone already knows it.
            Button(L10n.string("ios.pairing.send"), systemImage: "tv.badge.wifi") {
                sendingToTV = payload(for: server).map(IOSPairingRequest.init)
            }
        }
    }

    /// A failed sign-in used to show only after the library screen had already
    /// replaced this one, which read as nothing having happened.
    @ViewBuilder
    private var failureNote: some View {
        if opening == nil, case .failed(let message) = library.phase {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(IOSTheme.amber)
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink(L10n.string("legal.title")) {
                IOSLicensesView()
            }
        }
    }

    /// What to hand the television. The password comes out of the keychain here and
    /// goes no further than the sealed message.
    private func payload(for server: IOSSavedServer) -> PairingPayload? {
        switch server {
        case .synology(let connection):
            guard let password = synologyConnections.password(for: connection) else { return nil }
            return PairingPayload(
                name: connection.name,
                server: .synology(
                    baseURL: connection.baseURL,
                    account: connection.account,
                    password: password,
                    libraryPath: connection.libraryPath
                )
            )
        case .webDAV(let connection):
            guard let password = connections.password(for: connection) else { return nil }
            return PairingPayload(
                name: connection.name,
                server: .webDAV(
                    rootURL: connection.rootURL,
                    username: connection.username,
                    password: password,
                    libraryPath: connection.libraryPath
                )
            )
        }
    }

    private func open(_ server: IOSSavedServer) {
        opening = server.id
        switch server {
        case .synology(let connection): onUseSynology(connection)
        case .webDAV(let connection): onUseWebDAV(connection)
        }
        // The callers move to the library on success; if they do not, the spinner
        // must not be left turning for ever.
        Task {
            try? await Task.sleep(for: .seconds(20))
            opening = nil
        }
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            switch servers[index] {
            case .synology(let connection): synologyConnections.remove(connection)
            case .webDAV(let connection): connections.remove(connection)
            }
        }
    }
}

/// A payload on its way to a television, wrapped so it can drive a sheet.
struct IOSPairingRequest: Identifiable {
    let payload: PairingPayload
    var id: String { payload.name }
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
