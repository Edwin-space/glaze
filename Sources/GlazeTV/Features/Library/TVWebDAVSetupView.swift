import GlazeCore
import SwiftUI

/// Entering a NAS address on a television.
///
/// Typing anything with a remote is unpleasant, so this asks for the least it can: an
/// address, a username, a password. Everything else about the connection is derived.
struct TVWebDAVSetupView: View {
    let onSave: (WebDAVConnection, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            TVTheme.ground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                Text(L10n.string("webdav.add"))
                    .font(.system(size: 54, weight: .bold))

                Text(L10n.string("help.webdav.url"))
                    .font(.system(size: 24))
                    .foregroundStyle(TVTheme.dim)
                    .frame(maxWidth: 1000, alignment: .leading)

                TextField(L10n.string("webdav.field.name"), text: $name)
                TextField(L10n.string("webdav.field.url"), text: $address)
                TextField(L10n.string("webdav.field.username"), text: $username)
                SecureField(L10n.string("webdav.field.password"), text: $password)

                HStack(spacing: 20) {
                    Button(L10n.string("webdav.connect")) { save() }
                        .disabled(resolvedURL == nil)
                    Button(L10n.string("network.browser.close")) { dismiss() }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: 1100)
            .padding(60)
        }
        .onExitCommand { dismiss() }
    }

    /// Accepts an address typed without a scheme, which is what people type.
    private var resolvedURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)
    }

    private func save() {
        guard let url = resolvedURL else { return }
        let connection = WebDAVConnection(
            name: name.isEmpty ? (url.host ?? url.absoluteString) : name,
            rootURL: url,
            username: username
        )
        onSave(connection, password)
        dismiss()
    }
}
