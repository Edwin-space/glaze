import GlazeCore
import SwiftUI

/// Browsing a Synology needs a signed-in session first.
///
/// DSM has no anonymous listing: shares and folders are only visible to an account.
/// So this signs in, then hands the picker a way to list — and if the sign-in is what
/// fails, it says so here rather than showing an empty list of folders.
struct IOSSynologyFolderPicker: View {
    let connection: SynologyConnection
    let password: String
    let onChoose: (String) -> Void

    @State private var session: SynologySession?
    @State private var failure: String?

    var body: some View {
        Group {
            if let session {
                IOSFolderPicker(
                    folders: IOSRemoteFolders.synology(session: session),
                    onChoose: onChoose
                )
            } else if let failure {
                List {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(IOSTheme.amber)
                        Text(L10n.string("network.local_network.hint"))
                            .font(.caption)
                            .foregroundStyle(IOSTheme.dim)
                    }
                }
                .glazeListBackground()
                .navigationTitle(L10n.string("webdav.folder.title"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(IOSTheme.amber)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(IOSTheme.ground)
            }
        }
        .task { await signIn() }
    }

    private func signIn() async {
        guard session == nil else { return }
        do {
            session = try await SynologyClient().logIn(
                to: connection.baseURL,
                account: connection.account,
                password: password
            )
        } catch {
            failure = IOSLibraryModel.message(forSynology: error)
        }
    }
}
