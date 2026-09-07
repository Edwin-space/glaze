import AVFoundation
import GlazeCore
import SwiftUI

/// Reading the code a television is showing, and sending it a server.
struct IOSPairingScannerView: View {
    let payload: PairingPayload

    @Environment(\.dismiss) private var dismiss
    @State private var scanner = IOSQRScanner()
    @State private var status: Status = .looking
    @State private var failure: String?

    private enum Status: Equatable {
        case looking
        case sending
        case sent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                IOSCameraPreview(scanner: scanner).ignoresSafeArea()
                overlay
            }
            .navigationTitle(L10n.string("ios.pairing.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
            }
            .task {
                await scanner.start { code in
                    Task { await send(to: code) }
                }
            }
            .onDisappear { scanner.stop() }
        }
    }

    private var overlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                switch status {
                case .looking:
                    Label(L10n.string("ios.pairing.aim"), systemImage: "qrcode.viewfinder")
                case .sending:
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(L10n.string("ios.pairing.sending"))
                    }
                case .sent:
                    Label(L10n.string("ios.pairing.sent"), systemImage: "checkmark.circle.fill")
                }

                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(IOSTheme.amber)
                        .multilineTextAlignment(.center)
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.55))
        }
    }

    private func send(to code: String) async {
        guard status == .looking else { return }
        guard let invitation = PairingInvitation(encoded: code) else {
            failure = L10n.string("ios.pairing.not_a_code")
            return
        }

        status = .sending
        scanner.stop()
        do {
            try await PairingSender.send(payload, to: invitation)
            status = .sent
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        } catch {
            status = .looking
            failure = L10n.string("ios.pairing.failed")
            await scanner.start { code in Task { await send(to: code) } }
        }
    }
}

/// The camera, and the one thing we want out of it.
@Observable
@MainActor
final class IOSQRScanner {
    let session = AVCaptureSession()
    private let output = AVCaptureMetadataOutput()
    private var delegate: ScannerDelegate?
    private(set) var isDenied = false

    func start(onCode: @escaping @Sendable (String) -> Void) async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            isDenied = true
            return
        }
        guard !session.isRunning else { return }

        if session.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input), session.canAddOutput(output)
            else { return }
            session.addInput(input)
            session.addOutput(output)
            output.metadataObjectTypes = [.qr]
        }

        let delegate = ScannerDelegate(onCode: onCode)
        self.delegate = delegate
        output.setMetadataObjectsDelegate(delegate, queue: .main)

        // Starting the session blocks for a moment; keeping it off the main actor
        // stops the sheet from appearing frozen. The session is a reference type
        // Swift cannot prove is safe to send, and AVCaptureSession is documented as
        // safe to start and stop from any queue.
        nonisolated(unsafe) let session = session
        await Task.detached { session.startRunning() }.value
    }

    func stop() {
        guard session.isRunning else { return }
        nonisolated(unsafe) let session = session
        Task.detached { session.stopRunning() }
    }
}

private final class ScannerDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let onCode: @Sendable (String) -> Void

    init(onCode: @escaping @Sendable (String) -> Void) {
        self.onCode = onCode
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput objects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let code = objects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let text = code.stringValue
        else { return }
        onCode(text)
    }
}

struct IOSCameraPreview: UIViewRepresentable {
    let scanner: IOSQRScanner

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = scanner.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
