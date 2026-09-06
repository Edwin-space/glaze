import GlazeCore
import SwiftUI
import UniformTypeIdentifiers

/// Where the films come from: servers found on the network, and NAS addresses typed in.
struct IOSSourcesView: View {
    let discovery: NetworkMediaBrowserModel
    let connections: WebDAVConnectionStore
    let onUseDLNA: (NetworkMediaServer) -> Void
    let onUseWebDAV: (WebDAVConnection) -> Void

    @State private var isAdding = false
    @State private var isOpeningFile = false
    @State private var localFile: LocalFile?

    var body: some View {
        List {
            deviceSection

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
        .fileImporter(
            isPresented: $isOpeningFile,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let picked = urls.first else { return }
            localFile = LocalFile(url: picked)
        }
        .fullScreenCover(item: $localFile, onDismiss: { localFile?.release() }) { file in
            IOSPlayerView(resource: file.resource, title: file.url.lastPathComponent)
        }
    }

    /// A film already on the phone — downloaded on a train, or handed over by AirDrop.
    /// Everything else here needs a server; this does not.
    private var deviceSection: some View {
        Section {
            Button { isOpeningFile = true } label: {
                Label(L10n.string("ios.sources.open_file"), systemImage: "doc.badge.plus")
            }
        } header: {
            Text(L10n.string("ios.sources.device"))
        } footer: {
            Text(L10n.string("ios.sources.open_file.hint"))
        }
    }
}

/// A video picked out of Files.
///
/// The URL lives outside the sandbox, so access has to be claimed before playback and
/// given back after — and held for the whole film rather than copied, because these are
/// gigabytes.
final class LocalFile: Identifiable {
    let url: URL
    nonisolated var id: String { url.absoluteString }
    private let accessed: Bool

    init(url: URL) {
        self.url = url
        accessed = url.startAccessingSecurityScopedResource()
    }

    var resource: NetworkMediaResource {
        NetworkMediaResource(
            serverID: "device",
            objectID: url.path,
            playbackURL: url,
            byteCount: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) }
        )
    }

    func release() {
        if accessed { url.stopAccessingSecurityScopedResource() }
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
