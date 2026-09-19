import GlazeCore
import SwiftUI

/// Synology connections in Settings → Network.
///
/// The Mac could only reach a NAS over WebDAV, which has to be installed and switched
/// on in DSM first. Signing in to DSM the way DS File does needs nothing turned on at
/// all, which is why the phone has done it since `docs/35`.
struct MacSynologyCard: View {
    @State private var connections = SynologyConnectionStore()
    @State private var isAdding = false
    @State private var editing: SynologyConnection?
    @State private var pendingRemoval: SynologyConnection?

    var body: some View {
        SettingsCard(titleKey: "synology.section.title") {
            if connections.connections.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "externaldrive.badge.person.crop")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("settings.network.synology.empty"))
                            .font(.headline)
                        Text(L10n.string("settings.network.synology.empty_detail"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 18)

                    Button { isAdding = true } label: {
                        Label(L10n.string("synology.add"), systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            } else {
                ForEach(connections.connections) { connection in
                    row(connection)
                    if connection.id != connections.connections.last?.id { Divider() }
                }

                HStack {
                    Spacer()
                    Button { isAdding = true } label: {
                        Label(L10n.string("synology.add"), systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            MacSynologyEditorView { connection, password in
                connections.save(connection, password: password)
            }
        }
        .sheet(item: $editing) { connection in
            MacSynologyEditorView(
                connection: connection,
                storedPassword: connections.password(for: connection)
            ) { edited, password in
                connections.save(edited, password: password)
            }
        }
        .confirmationDialog(
            L10n.string("synology.remove.confirm"),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { connection in
            Button(L10n.string("common.delete"), role: .destructive) {
                connections.remove(connection)
                pendingRemoval = nil
            }
            Button(L10n.string("settings.cancel"), role: .cancel) { pendingRemoval = nil }
        } message: { connection in
            Text(String(format: L10n.string("synology.remove.detail"), connection.name))
        }
    }

    private func row(_ connection: SynologyConnection) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name).font(.headline)
                Text(subtitle(for: connection))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            Menu {
                Button(L10n.string("settings.edit")) { editing = connection }
                Divider()
                Button(L10n.string("synology.remove"), role: .destructive) { pendingRemoval = connection }
            } label: {
                Label(L10n.string("settings.more"), systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func subtitle(for connection: SynologyConnection) -> String {
        let host = connection.baseURL.host ?? connection.baseURL.absoluteString
        guard let path = connection.libraryPath, !path.isEmpty else { return host }
        return "\(host) · \(path)"
    }
}

/// Signing in to a NAS, and choosing which shared folder to open.
///
/// The address is asked for as a host name and a domain rather than as a URL. Someone
/// who turned on DDNS in DSM chose exactly those two things there, and typing
/// `https://` and `:5001` back afterwards is how people end up on port 5000, or on an
/// IP address whose certificate cannot verify.
struct MacSynologyEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let connectionID: String
    private let storedPassword: String?
    private let onSave: (SynologyConnection, String?) -> Void

    @State private var name: String
    @State private var hostName: String
    @State private var domain: String
    @State private var typedAddress: String
    @State private var account: String
    @State private var password = ""
    @State private var oneTimeCode = ""
    @State private var needsOneTimeCode = false
    @State private var isWorking = false
    @State private var failure: String?
    @State private var untrusted: ServerCertificate?
    @State private var session: SynologySession?
    @State private var shares: [SynologyEntry] = []
    @State private var libraryPath: String?

    /// What the domain menu calls the option for typing the whole address.
    private static let typedAddressOption = ""

    init(
        connection: SynologyConnection? = nil,
        storedPassword: String? = nil,
        onSave: @escaping (SynologyConnection, String?) -> Void
    ) {
        connectionID = connection?.id ?? UUID().uuidString
        self.storedPassword = storedPassword
        self.onSave = onSave
        _name = State(initialValue: connection?.name ?? "")
        _account = State(initialValue: connection?.account ?? "")
        _libraryPath = State(initialValue: connection?.libraryPath)

        // An existing connection is split back into a name and a domain when it was
        // made that way, so editing it shows what was typed rather than a URL. A new
        // one starts on the DDNS domain nearly every Synology at home is reached by.
        let host = connection?.baseURL.host ?? ""
        let matchedDomain = SynologyAddress.ddnsDomains.first { host.hasSuffix(".\($0)") }
        if let matchedDomain {
            _hostName = State(initialValue: String(host.dropLast(matchedDomain.count + 1)))
            _domain = State(initialValue: matchedDomain)
            _typedAddress = State(initialValue: "")
        } else if let connection {
            _hostName = State(initialValue: "")
            _domain = State(initialValue: Self.typedAddressOption)
            _typedAddress = State(initialValue: connection.baseURL.absoluteString)
        } else {
            _hostName = State(initialValue: "")
            _domain = State(initialValue: SynologyAddress.defaultDDNSDomain)
            _typedAddress = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if session == nil { signIn } else { shareChoice }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.string(session == nil ? "synology.title" : "synology.shares"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("settings.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if session == nil {
                        Button(L10n.string("synology.connect")) { Task { await connect() } }
                            .disabled(!canConnect || isWorking)
                    } else {
                        Button(L10n.string("settings.save")) { save() }
                    }
                }
            }
            .sheet(
                isPresented: Binding(get: { untrusted != nil }, set: { if !$0 { untrusted = nil } })
            ) {
                trustSheet
            }
        }
        .frame(width: 520, height: 470)
        .preferredColorScheme(.dark)
    }

    // MARK: - Signing in

    @ViewBuilder
    private var signIn: some View {
        Section {
            if domain == Self.typedAddressOption {
                TextField(L10n.string("synology.field.address"), text: $typedAddress)
            } else {
                TextField(L10n.string("synology.field.host_name"), text: $hostName)
            }

            Picker(L10n.string("synology.field.domain"), selection: $domain) {
                ForEach(SynologyAddress.ddnsDomains, id: \.self) { candidate in
                    Text(".\(candidate)").tag(candidate)
                }
                Divider()
                Text(L10n.string("synology.field.domain.custom")).tag(Self.typedAddressOption)
            }
        } header: {
            Text(L10n.string("synology.section.address"))
        } footer: {
            if let resolved = resolvedURL {
                Text(resolved.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(L10n.string(
                    domain == Self.typedAddressOption
                        ? "synology.field.address.hint"
                        : "synology.field.host_name.hint"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        Section {
            TextField(L10n.string("synology.field.account"), text: $account)
            SecureField(L10n.string("synology.field.password"), text: $password)
            if needsOneTimeCode {
                TextField(L10n.string("synology.field.otp"), text: $oneTimeCode)
            }
        } footer: {
            if needsOneTimeCode {
                Text(L10n.string("synology.field.otp.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if isWorking {
            Section {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.string("synology.connecting")).foregroundStyle(.secondary)
                }
            }
        }

        if let failure {
            Section {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
            }
        }
    }

    // MARK: - Choosing a folder

    @ViewBuilder
    private var shareChoice: some View {
        Section {
            TextField(L10n.string("synology.field.name"), text: $name)
        } footer: {
            Text(L10n.string("synology.field.name.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Button {
                libraryPath = nil
            } label: {
                shareRow(
                    title: L10n.string("synology.shares.all"),
                    detail: L10n.string("synology.shares.all.detail"),
                    isSelected: libraryPath == nil
                )
            }
            .buttonStyle(.plain)

            ForEach(shares) { share in
                Button { libraryPath = share.path } label: {
                    shareRow(title: share.name, detail: share.path, isSelected: libraryPath == share.path)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(L10n.string("synology.shares"))
        }
    }

    private func shareRow(title: String, detail: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Work

    private var resolvedURL: URL? {
        domain == Self.typedAddressOption
            ? SynologyAddress.compose(hostName: typedAddress, domain: "")
            : SynologyAddress.compose(hostName: hostName, domain: domain)
    }

    private var canConnect: Bool {
        resolvedURL != nil
            && !account.trimmingCharacters(in: .whitespaces).isEmpty
            && !(password.isEmpty && storedPassword == nil)
    }

    private func connect() async {
        guard let baseURL = resolvedURL else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }

        do {
            let candidatePassword = password.isEmpty ? (storedPassword ?? "") : password
            let session = try await SynologyClient().logIn(
                to: baseURL,
                account: account.trimmingCharacters(in: .whitespaces),
                password: candidatePassword,
                oneTimeCode: oneTimeCode.isEmpty ? nil : oneTimeCode
            )
            self.session = session
            shares = (try? await SynologyClient().shares(session)) ?? []
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = baseURL.host.map { $0.components(separatedBy: ".").first ?? $0 } ?? ""
            }
        } catch SynologyError.needsOneTimeCode {
            needsOneTimeCode = true
            failure = L10n.string("synology.error.otp_required")
        } catch SynologyError.certificateUntrusted(let certificate) {
            untrusted = certificate
        } catch {
            failure = SynologyErrorMessage.text(for: error)
        }
    }

    private func save() {
        guard let baseURL = resolvedURL else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let connection = SynologyConnection(
            id: connectionID,
            name: trimmedName.isEmpty ? (baseURL.host ?? baseURL.absoluteString) : trimmedName,
            baseURL: baseURL,
            account: account.trimmingCharacters(in: .whitespaces),
            libraryPath: libraryPath
        )
        onSave(connection, password.isEmpty ? storedPassword : password)
        dismiss()
    }

    /// A NAS out of the box presents a certificate nothing vouches for. The viewer
    /// compares the fingerprint and decides — rather than being told "could not
    /// connect" about a NAS that is answering perfectly well.
    @ViewBuilder
    private var trustSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let certificate = untrusted {
                Text(L10n.string("synology.trust.title")).font(.title2.weight(.semibold))
                Text(L10n.string("synology.error.certificate_untrusted"))
                    .fixedSize(horizontal: false, vertical: true)
                Text(certificate.fingerprint)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button(L10n.string("common.close")) { untrusted = nil }
                    Spacer()
                    Button(L10n.string("synology.trust.accept")) {
                        ServerTrustStore.shared.accept(certificate)
                        untrusted = nil
                        Task { await connect() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
