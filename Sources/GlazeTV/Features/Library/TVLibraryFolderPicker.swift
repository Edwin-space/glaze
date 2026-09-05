import GlazeCore
import SwiftUI

/// Asks which folder on the NAS holds the films.
///
/// A WebDAV root is every share the account can see — photographs, home directories,
/// a music library, a wastebasket. Reading a library from there means reading the whole
/// disk: slow enough to look broken, and heavy enough that the television gives up on
/// the app. One question, asked once, avoids all of it.
struct TVLibraryFolderPicker: View {
    let connection: WebDAVConnection
    let password: String?
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var folders: [WebDAVEntry] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("tv.library.folder.title"))
                    .font(.system(size: 52, weight: .bold))
                Text(String(format: L10n.string("tv.library.folder.detail_format"), connection.name))
                    .font(.system(size: 25))
                    .foregroundStyle(TVTheme.dim)
            }

            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 84)
        .padding(.top, 70)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TVTheme.ground.ignoresSafeArea())
        .onExitCommand { dismiss() }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 20) {
                ProgressView().controlSize(.large)
                Text(L10n.string("tv.library.folder.reading"))
                    .font(.system(size: 27))
                    .foregroundStyle(TVTheme.dim)
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 25))
                .foregroundStyle(TVTheme.dim)
                .frame(maxWidth: 1100, alignment: .leading)
        case .ready:
            ScrollView {
                VStack(spacing: 14) {
                    // The whole share stays available for anyone who really keeps
                    // films at the top level.
                    folderRow(
                        title: L10n.string("tv.library.folder.whole_share"),
                        symbol: "externaldrive",
                        path: ""
                    )
                    ForEach(folders) { folder in
                        folderRow(title: folder.name, symbol: "folder", path: folder.name)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func folderRow(title: String, symbol: String, path: String) -> some View {
        Button {
            onChoose(path)
            dismiss()
        } label: {
            HStack(spacing: 22) {
                Image(systemName: symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(TVTheme.amber)
                Text(title)
                    .font(.system(size: 30, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(TVTheme.dim)
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.card)
    }

    private func load() async {
        let credentials = password.map { (username: connection.username, password: $0) }
        do {
            let entries = try await WebDAVClient().list(connection.rootURL, credentials: credentials)
            folders = entries
                .filter { $0.isDirectory && !$0.isHidden && $0.url != connection.rootURL }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            phase = .ready
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case WebDAVError.unauthorized: L10n.string("webdav.error.unauthorized")
        case WebDAVError.notFound: L10n.string("webdav.error.not_found")
        case WebDAVError.notWebDAV: L10n.string("webdav.error.not_webdav")
        case WebDAVError.certificateMismatch: L10n.string("webdav.error.certificate")
        default: L10n.string("webdav.error.network")
        }
    }
}
