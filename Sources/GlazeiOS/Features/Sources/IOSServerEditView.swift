import GlazeCore
import SwiftUI

/// Changing a server that is already saved.
///
/// Until this existed the only way to correct a typed address, or to update a
/// password after changing it on the NAS, was to delete the server and add it again
/// — losing nothing but making the app feel like it could not be corrected.
struct IOSServerEditView: View {
    let server: IOSSavedServer
    let connections: WebDAVConnectionStore
    let synologyConnections: SynologyConnectionStore
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var account = ""
    @State private var password = ""
    @State private var folder = ""
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("webdav.field.name"), text: $name)
                    TextField(L10n.string("synology.field.address"), text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField(L10n.string("synology.field.account"), text: $account)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(server.kind.title)
                }

                Section {
                    SecureField(L10n.string("synology.field.password"), text: $password)
                } footer: {
                    // Leaving it blank is the safe default: the stored password is
                    // never shown, so an empty field must not mean "clear it".
                    Text(L10n.string("ios.server.edit.password.hint"))
                }

                // Browsed, not typed. A path typed from memory is wrong often enough
                // that the result — an empty library with nothing to say why — is the
                // commonest way this screen wastes someone's evening.
                Section {
                    NavigationLink {
                        folderPicker
                    } label: {
                        LabeledContent(L10n.string("ios.server.edit.folder")) {
                            Text(folder.isEmpty ? L10n.string("webdav.folder.root") : folder)
                                .foregroundStyle(folder.isEmpty ? IOSTheme.dim : IOSTheme.amber)
                        }
                    }
                } footer: {
                    Text(L10n.string("ios.server.edit.folder.hint"))
                }
            }
            .glazeListBackground()
            .navigationTitle(L10n.string("ios.server.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.save")) { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && SynologyAddress.normalised(address) != nil
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        switch server {
        case .synology(let connection):
            name = connection.name
            address = connection.baseURL.absoluteString
            account = connection.account
            folder = connection.libraryPath ?? ""
        case .webDAV(let connection):
            name = connection.name
            address = connection.rootURL.absoluteString
            account = connection.username
            folder = connection.libraryPath ?? ""
        }
    }

    /// Synology needs a signed-in session before anything can be listed, so the
    /// password is asked for here if it is not already in the keychain.
    @ViewBuilder
    private var folderPicker: some View {
        switch server {
        case .webDAV(let connection):
            IOSFolderPicker(
                folders: IOSRemoteFolders.webDAV(
                    connection: connection,
                    password: password.isEmpty ? connections.password(for: connection) : password
                ),
                onChoose: { folder = $0 }
            )
        case .synology(let connection):
            IOSSynologyFolderPicker(
                connection: connection,
                password: password.isEmpty
                    ? (synologyConnections.password(for: connection) ?? "")
                    : password,
                onChoose: { folder = $0 }
            )
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAccount = account.trimmingCharacters(in: .whitespaces)
        let trimmedFolder = folder.trimmingCharacters(in: .whitespaces)
        // Blank means "leave the stored one alone", not "there is no password".
        let newPassword = password.isEmpty ? nil : password

        switch server {
        case .synology(var connection):
            guard let baseURL = SynologyAddress.normalised(address) else { return }
            connection.name = trimmedName
            connection.baseURL = baseURL
            connection.account = trimmedAccount
            connection.libraryPath = trimmedFolder.isEmpty ? nil : trimmedFolder
            synologyConnections.save(connection, password: newPassword)

        case .webDAV(var connection):
            guard let rootURL = URL(string: address.trimmingCharacters(in: .whitespaces)),
                  rootURL.host != nil else { return }
            connection.name = trimmedName
            connection.rootURL = rootURL
            connection.username = trimmedAccount
            connection.libraryPath = trimmedFolder.isEmpty ? nil : trimmedFolder
            connections.save(connection, password: newPassword)
        }

        onSaved()
        dismiss()
    }
}
