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
        } catch {
            failure = IOSLibraryModel.message(forSynology: error)
        }
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
