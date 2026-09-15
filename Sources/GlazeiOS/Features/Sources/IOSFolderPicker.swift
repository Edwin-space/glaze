import GlazeCore
import SwiftUI

/// One folder on a server.
struct IOSRemoteFolder: Identifiable, Equatable {
    /// Path relative to the share's root, e.g. `video/영화`.
    let path: String
    let name: String

    var id: String { path }
}

/// Browses a server and asks which folder holds the films.
///
/// The alternative was a text field asking for a path. Nobody remembers the exact
/// spelling of a folder three levels down on a NAS, and getting it wrong produces an
/// empty library with nothing to say why. Reading a share's root instead of a chosen
/// folder is worse: it walks the whole disk — photographs, backups, home directories
/// — slowly enough to look broken.
///
/// Pushed rather than presented, so it works from inside a sheet the way a sheet
/// inside a sheet does not.
struct IOSFolderPicker: View {
    /// Lists the folders directly inside a path. `""` is the share's root.
    let folders: (String) async throws -> [IOSRemoteFolder]
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var entries: [IOSRemoteFolder] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        List {
            Section {
                Button(L10n.string("webdav.folder.choose_here")) {
                    onChoose(path)
                    dismiss()
                }
                .disabled(phase == .loading)
            } header: {
                Text(path.isEmpty ? L10n.string("webdav.folder.root") : path)
                    .textCase(nil)
            } footer: {
                Text(L10n.string("webdav.folder.detail"))
            }

            if !path.isEmpty {
                Section {
                    Button {
                        go(to: parent(of: path))
                    } label: {
                        Label(L10n.string("webdav.folder.up"), systemImage: "arrow.turn.left.up")
                    }
                }
            }

            Section {
                switch phase {
                case .loading:
                    HStack(spacing: IOSTheme.Spacing.small) {
                        ProgressView()
                        Text(L10n.string("webdav.folder.reading"))
                            .foregroundStyle(IOSTheme.dim)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(IOSTheme.amber)
                case .ready:
                    if entries.isEmpty {
                        Text(L10n.string("webdav.folder.empty"))
                            .font(.footnote)
                            .foregroundStyle(IOSTheme.dim)
                    }
                    ForEach(entries) { folder in
                        Button { go(to: folder.path) } label: {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(IOSTheme.dim)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .glazeListBackground()
        .navigationTitle(L10n.string("webdav.folder.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func go(to next: String) {
        path = next
        Task { await load() }
    }

    private func parent(of path: String) -> String {
        var parts = path.split(separator: "/").map(String.init)
        if !parts.isEmpty { parts.removeLast() }
        return parts.joined(separator: "/")
    }

    private func load() async {
        phase = .loading
        do {
            entries = try await folders(path)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            phase = .ready
        } catch {
            phase = .failed(IOSLibraryModel.message(forSynology: error))
        }
    }
}
