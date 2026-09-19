import GlazeCore
import SwiftUI

/// Adding a DLNA server by typing where it is.
///
/// Automatic discovery shouts at the whole network, and an Apple TV is not allowed to
/// do that without an entitlement Apple grants by application (`docs/34`). Until then
/// the list on the previous screen is empty however well the NAS is working. Asking
/// one server directly needs no permission at all.
struct TVAddMediaServerView: View {
    let onAdd: (NetworkMediaServer) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("network.manual.title"))
                    .font(.system(size: 52, weight: .bold))
                Text(L10n.string("network.manual.detail"))
                    .font(.system(size: 24))
                    .foregroundStyle(TVTheme.dim)
                    .frame(maxWidth: 1_100, alignment: .leading)
            }

            TextField(L10n.string("network.manual.field"), text: $address)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(maxWidth: 900)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(TVTheme.amber)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            HStack(spacing: 20) {
                Button(L10n.string("common.cancel")) { dismiss() }
                Button {
                    Task { await add() }
                } label: {
                    HStack(spacing: 12) {
                        if isWorking { ProgressView() }
                        Text(L10n.string("network.manual.add"))
                    }
                }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }

            Text(L10n.string("network.manual.hint"))
                .font(.system(size: 20))
                .foregroundStyle(TVTheme.dim)
                .frame(maxWidth: 1_100, alignment: .leading)
        }
        .padding(84)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TVTheme.ground.ignoresSafeArea())
    }

    private func add() async {
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            let server = try await UPnPServerLocator().locate(address)
            onAdd(server)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
