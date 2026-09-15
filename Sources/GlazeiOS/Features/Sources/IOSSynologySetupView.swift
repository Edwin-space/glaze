import GlazeCore
import SwiftUI

/// Signing in to a Synology, and choosing which shared folder to open.
///
/// DS File asks for an address, an account and a password, and that is all Glaze
/// asks for either. WebDAV does not have to be switched on in DSM first, which is
/// the step that stopped most people.
struct IOSSynologySetupView: View {
    let onConnected: (SynologyConnection, String, SynologySession, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var account = ""
    @State private var password = ""
    @State private var oneTimeCode = ""
    @State private var needsOneTimeCode = false
    @State private var isWorking = false
    @State private var failure: String?
    /// A certificate the NAS presented that nothing vouches for. Shown so the viewer
    /// can compare the fingerprint and decide, rather than being told "could not
    /// connect" about a NAS that is answering perfectly well.
    @State private var untrusted: ServerCertificate?

    @State private var session: SynologySession?
    @State private var shares: [SynologyEntry] = []

    var body: some View {
        NavigationStack {
            Form {
                if session == nil {
                    signIn
                } else {
                    shareChoice
                }
            }
            .glazeListBackground()
            .navigationTitle(L10n.string(session == nil ? "synology.title" : "synology.shares"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
            }
            .sheet(
                isPresented: Binding(get: { untrusted != nil }, set: { if !$0 { untrusted = nil } })
            ) {
                trustSheet
            }
        }
    }

    // MARK: - Signing in

    @ViewBuilder
    private var signIn: some View {
        Section {
            TextField(L10n.string("synology.field.address"), text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField(L10n.string("synology.field.account"), text: $account)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(L10n.string("synology.field.password"), text: $password)
        } footer: {
            Text(L10n.string("synology.field.address.hint"))
        }

        if needsOneTimeCode {
            Section {
                TextField(L10n.string("synology.field.otp"), text: $oneTimeCode)
                    .keyboardType(.numberPad)
            } footer: {
                Text(L10n.string("synology.field.otp.hint"))
            }
        }

        if failure != nil {
            Text(L10n.string("network.local_network.hint"))
                .font(.caption)
                .foregroundStyle(IOSTheme.dim)
        }
        if let failure {
            Section {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(IOSTheme.amber)
            }
        }

        Section {
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if isWorking { ProgressView().padding(.trailing, IOSTheme.Spacing.tight) }
                    Text(L10n.string("synology.connect"))
                }
            }
            .disabled(!canConnect || isWorking)
        }
    }

    private var canConnect: Bool {
        SynologyAddress.normalised(address) != nil
            && !account.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    private func connect() async {
        guard let baseURL = SynologyAddress.normalised(address) else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }

        // Say this before the attempt rather than after a puzzling connection error.
        if SynologyAddress.needsHTTPS(baseURL) {
            failure = L10n.string("synology.error.needs_https")
            return
        }

        let client = SynologyClient()
        do {
            let signedIn = try await client.logIn(
                to: baseURL,
                account: account.trimmingCharacters(in: .whitespaces),
                password: password,
                oneTimeCode: needsOneTimeCode ? oneTimeCode : nil
            )
            shares = try await client.shares(signedIn).filter { !$0.isHidden }
            session = signedIn
        } catch SynologyError.needsOneTimeCode {
            needsOneTimeCode = true
            failure = L10n.string("synology.error.otp_required")
        } catch SynologyError.certificateUntrusted(let certificate) {
            untrusted = certificate
        } catch {
            failure = IOSLibraryModel.message(forSynology: error)
        }
    }

    /// Takes the name off the certificate and connects to that instead. No override:
    /// with the right address the certificate verifies normally.
    private func useCertifiedName(_ name: String) {
        // Whatever else was typed — a port, a scheme — is kept; only the host changes.
        address = address.replacingOccurrences(
            of: untrusted?.host ?? "",
            with: name
        )
        untrusted = nil
        Task { await connect() }
    }

    private var trustTitleKey: String {
        if case .useCertifiedName? = untrusted.map(ServerTrustPrompt.init) { return "network.name.title" }
        return "network.trust.title"
    }

    private func trustAndRetry(_ certificate: ServerCertificate) {
        ServerTrustStore.shared.accept(certificate)
        untrusted = nil
        Task { await connect() }
    }

    /// Deliberately a sheet the viewer has to read, not a toggle buried in settings.
    /// Accepting pins this one certificate for this one host; a different one later
    /// is refused again.
    private var trustSheet: some View {
        NavigationStack {
            Form {
                if case .useCertifiedName(let name, _)? = untrusted.map(ServerTrustPrompt.init) {
                    // Nothing is wrong with this server. Offering "trust anyway" here
                    // would teach someone to wave away a warning that is telling them
                    // the truth, when one tap fixes it properly.
                    Section {
                        Text(String(format: L10n.string("network.name.detail"), name))
                            .font(.callout)
                    } header: {
                        Text(L10n.string("network.name.title"))
                    }

                    Section {
                        Button(String(format: L10n.string("network.name.use"), name)) {
                            useCertifiedName(name)
                        }
                    }
                } else {
                    Section {
                        Text(L10n.string("network.trust.detail"))
                            .font(.callout)
                    } header: {
                        Text(L10n.string("synology.error.certificate_untrusted"))
                    }

                    if let untrusted {
                        Section(L10n.string("network.trust.fingerprint")) {
                            LabeledContent(untrusted.host) { EmptyView() }
                            Text(untrusted.fingerprint)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            if untrusted.summary != untrusted.host {
                                Text(untrusted.summary)
                                    .font(.caption)
                                    .foregroundStyle(IOSTheme.dim)
                            }
                        }

                        Section {
                            Button(L10n.string("network.trust.accept")) { trustAndRetry(untrusted) }
                        }
                    }
                }
            }
            .glazeListBackground()
            .navigationTitle(L10n.string(trustTitleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.close")) { untrusted = nil }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(IOSTheme.ground)
    }

    // MARK: - Choosing a folder

    @ViewBuilder
    private var shareChoice: some View {
        Section {
            ForEach(shares) { share in
                Button {
                    finish(with: share.path)
                } label: {
                    Label(share.name, systemImage: "folder")
                }
            }
        } footer: {
            Text(L10n.string("synology.shares.detail"))
        }
    }

    private func finish(with path: String) {
        guard let baseURL = SynologyAddress.normalised(address), let session else { return }
        let host = baseURL.host ?? address
        let connection = SynologyConnection(
            name: host,
            baseURL: baseURL,
            account: account.trimmingCharacters(in: .whitespaces),
            libraryPath: path
        )
        onConnected(connection, password, session, path)
        dismiss()
    }
}
