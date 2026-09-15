import Foundation

/// What to tell someone whose server would not connect, and what to offer them.
///
/// The phone learned this the hard way and the other two apps had not: a Synology that
/// refuses a connection leaves a person staring at "could not connect" with nothing to
/// do. There are two quite different situations behind that, and they want opposite
/// advice — which is why this is a decision worth making in one place rather than three.
public enum ServerTrustPrompt: Equatable, Sendable {
    /// The certificate is properly issued, just to a different name than the address
    /// that was typed. Almost always a NAS reached by its IP address: DSM has a real
    /// Let's Encrypt certificate for its `*.synology.me` name.
    ///
    /// Overriding the check here would be the wrong advice — the warning is telling the
    /// truth, and one tap fixes it properly.
    case useCertifiedName(String, ServerCertificate)

    /// Nobody vouches for this certificate, which is what a NAS out of the box looks
    /// like. The viewer compares the fingerprint with their own and decides.
    case trustCertificate(ServerCertificate)

    /// The rule itself: a certificate that would verify under another name wants the
    /// address changed; anything else wants the viewer to look at the fingerprint.
    public init(_ certificate: ServerCertificate) {
        if let name = certificate.certifiedName {
            self = .useCertifiedName(name, certificate)
        } else {
            self = .trustCertificate(certificate)
        }
    }

    /// Reached by asking the trust store what it saw for this host.
    ///
    /// - Parameter error: nil when the caller already knows the failure was a handshake.
    public static func forHost(
        _ host: String,
        error: Error? = nil,
        store: ServerTrustStore = .shared
    ) -> ServerTrustPrompt? {
        // Offering to trust a certificate for a timeout taught people to wave away
        // warnings that meant nothing, so the failure has to be one of these.
        if let error {
            let isHandshake = (error as? URLError).map(ServerTrust.mayBeHandshake) ?? false
            guard isHandshake || Self.isCertificateError(error) else { return nil }
        }
        guard let certificate = store.refused(for: host) else { return nil }
        return ServerTrustPrompt(certificate)
    }

    private static func isCertificateError(_ error: Error) -> Bool {
        switch error {
        case SynologyError.certificateUntrusted, WebDAVError.certificateMismatch: true
        default: false
        }
    }
}
