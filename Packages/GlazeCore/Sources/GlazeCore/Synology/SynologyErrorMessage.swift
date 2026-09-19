import Foundation

/// What to tell someone whose NAS refused them.
///
/// Written once and shared: the phone and the Mac sign in to the same DSM with the
/// same client, and two copies of this list drifted the moment one of them gained a
/// case the other did not.
public enum SynologyErrorMessage {
    public static func text(for error: Error) -> String {
        switch error {
        case SynologyError.badCredentials: L10n.string("synology.error.credentials")
        case SynologyError.needsOneTimeCode: L10n.string("synology.error.otp_required")
        case SynologyError.oneTimeCodeRejected: L10n.string("synology.error.otp_rejected")
        case SynologyError.accountDisabled: L10n.string("synology.error.disabled")
        case SynologyError.notSynology: L10n.string("synology.error.not_synology")
        case SynologyError.insecureConnectionBlocked: L10n.string("synology.error.needs_https")
        case SynologyError.certificateUntrusted: L10n.string("synology.error.certificate_untrusted")
        // What the system actually said, rather than "could not connect" — which is
        // true of every failure and therefore useless. A refused port, a name that
        // does not resolve and a timeout each need a different thing done about them.
        case SynologyError.transport(let detail):
            String(format: L10n.string("synology.error.transport_format"), detail)
        default: L10n.string("webdav.error.network")
        }
    }
}
