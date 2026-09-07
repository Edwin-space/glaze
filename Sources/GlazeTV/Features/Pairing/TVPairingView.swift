import CoreImage.CIFilterBuiltins
import GlazeCore
import SwiftUI

/// Taking a server from the phone instead of typing it on a remote control.
///
/// The television shows a code, the phone reads it with its camera, and the
/// connection comes across. The key that protects it is inside the code on screen and
/// never touches the network — a NAS password should not cross even a home network in
/// the clear.
struct TVPairingView: View {
    let onPaired: (PairingPayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var invitation: PairingInvitation?
    @State private var failure: String?
    @State private var receiver = PairingReceiver()

    var body: some View {
        VStack(spacing: 44) {
            VStack(spacing: 14) {
                Text(L10n.string("tv.pairing.title"))
                    .font(.system(size: 54, weight: .bold))
                Text(L10n.string("tv.pairing.detail"))
                    .font(.system(size: 27))
                    .foregroundStyle(TVTheme.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1100)
            }

            code

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(TVTheme.amber)
            }

            Text(L10n.string("tv.pairing.steps"))
                .font(.system(size: 24))
                .foregroundStyle(TVTheme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1000)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TVTheme.ground)
        .onExitCommand { dismiss() }
        .task { await listen() }
    }

    @ViewBuilder
    private var code: some View {
        if let invitation, let image = Self.qrCode(for: invitation.encoded) {
            VStack(spacing: 18) {
                image
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 380, height: 380)
                    // A code is read from its contrast; the app's dark ground would
                    // fight it, so it keeps its own white surround.
                    .padding(24)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("\(invitation.host):\(invitation.port)")
                    .font(.system(size: 22).monospaced())
                    .foregroundStyle(.white.opacity(0.35))
            }
        } else {
            ProgressView().controlSize(.large).frame(height: 380)
        }
    }

    private func listen() async {
        do {
            invitation = try await receiver.start()
            let payload = try await receiver.waitForServer()
            onPaired(payload)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            failure = L10n.string("tv.pairing.failed")
        }
    }

    private static func qrCode(for text: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // Medium correction: enough to survive a television's glare without making
        // the code so dense a phone across the room cannot resolve it.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
